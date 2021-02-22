/***
* Name: Bicycle model v.2.0
* Author: Dana Kaziyeva, Gudrun Wallentin, Martin Loidl
* Description: The purpose of the model is to generate disaggregated traffic flow distribution of cyclists at the regional scale level. 
* The human decision-making is based on derived assumptions from the mobility survey data. 
* The model's result is the emergent bicycle traffic flow pattern at the high spatial and temporal level of detail.
* To use it for another study area: change input data: fileHomePlaces, fileWorkPlaces, fileFacilities, fileCountingStations, fileRoads, 
* fileIntersections, fileCityOutline, fileRegionOutline
***/

model bicyclemodel

global{
	// Input data
	file fileHomePlaces <- file("../includes/model_input/shapefiles/homes.shp"); //residential data (250m resolution) with demographic attributes
	file fileWorkPlaces <- file("../includes/model_input/shapefiles/workplaces.shp"); //employees data (100m resolution) with the attribute of the number of registered employees
	file fileFacilities <- file("../includes/model_input/shapefiles/facilities.shp"); //facilities dataset
	file fileCountingStations <- file("../includes/model_input/shapefiles/counting_stations.shp");//bicycle counting stations dataset
	file fileRoads <- shape_file("../includes/model_input/shapefiles/network.shp"); //network dataset with "null" values represented as "-9999"
	file fileIntersections <- file("../includes/model_input/shapefiles/intersections.shp"); //street intersections dataset
	file fileCityOutline<- file("../includes/model_input/shapefiles/outline_city.shp"); //city outline dataset
	file fileRegionOutline<- file("../includes/model_input/shapefiles/outline_region.shp"); //region outline dataset
	
	matrix activityMatrix <- matrix(file("../includes/model_input/csv_files/activity_probabilities.csv")); //activity probabilities by position
	matrix timeMatrix <- matrix(file("../includes/model_input/csv_files/time_probabilities.csv")); //departure time probabilities by activity type and by hour
	matrix modeMatrix <- matrix(file("../includes/model_input/csv_files/mode_probabilities.csv")); //mode probabilities by activity type and spatial extent: city/region
	matrix durationMatrix <- matrix(file("../includes/model_input/csv_files/work_duration_probabilities.csv")); //work duration probabilities by gender
	matrix countsMatrix <- matrix(file("../includes/model_input/csv_files/hourly_counts_stations.csv")); //observed counting data at counting stations for validation. Time interval should be the same as the "countingStationTimeInterval"
	
	//Output data path names
	string heatmapFileName <- "../includes/model_output/heatmap.shp"; //the heatmap of bicycle traffic volume on a network
	string activeCyclistsFileName <- "../includes/model_output/active_cyclists.csv";// the number of moving cyclists by trip purpose
	string countsFileName <- "../includes/model_output/counts.csv"; //the number of traversed cyclists at counting stations
	string tripsFileName<- "../includes/model_output/trips.txt"; //bicycle trips with travel information
	
	//Model parameters
	geometry shape<- envelope(fileRegionOutline)+envelope(fileHomePlaces)+envelope(fileWorkPlaces); //spatial extent
	geometry cityOutline; //city boundaries
	float step <- 1 #mn; //simulation step: 1 minute
	float simulationStartTime; //machine time at the beginning of simulation run (excluding initialization time)
	int networkTimeInterval; //the user-defined time interval to save the number of traverses on a network, in cycles (= minutes)
	int countingStationTimeInterval; //the user-defined time interval to save the number of traverses at stations, in cycles (= minutes)
	int activeCylistsTimeInterval; //the user-defined time interval to save the number of actively moving cyclists, in cycles (= minutes)
	
	//Network variables
	graph theGraph; //bidirectional network graph composed of road species
	map<road,float> perimeterWeights; //perimeter weights for roads
	map<road,float> cyclingWeights; //road weights that define routing behaviour of cyclists
	string routingAlgorithm; //user-defined routing algorithm for cyclists: "shortest path", "safest path". Deafault is "safest path".
	
	//Attribute weights needed for network assessment and calculation of safety index
	float bicycleInfrastructureWeight; //weight for bicycle infrastructure
	float mitVolumeWeight; //weight for motorized traffic volume attribute
	float designatedRouteWeight; //weight for designated route attribute
	float roadCategoryWeight; //weight for road category attribute
	float maxSpeedWeight; //weight for maximal speed attribute
	float adjacentEdgeWeight; //weight for adjacent edge attribute
	float parkingWeight; //weight for parking attribute
	float pavementWeight; //weight for pavement attribute
	float widthLaneWeight; //weight for width lane attribute
	float gradientWeight; //weight for gradient attribute
	float railsWeight; //weight for rails attribute
	float numberLaneWeight; //weight for lane number attribute
	float landuseWeight; //weight for landuse attribute
	float designatedRouteAdjusted; //adjusted weight for constraction status attribute
	float railsAdjusted; //adjusted weight for rails attribute
	float pavementAdjusted; //adjusted weight for pavement
	float gradientAdjusted; //adjusted weight for gradient
	float bridgeValue; //bridge value
	float pushValue; //push value
	
	//Activity probabilities depending on employment_status and activity position (ordinal number of activity in activity chain, 0-7). Activity types: "home","other_place","work","business","education"("school","university"),"shop","authority","doctor","recreation","bringing"
	map<string,map<int,map<string,float>>> activityProbabilities;
	
	//Starting time probabilities by activity type and actvity position (0-7). The distribution of the departure time probabilities is represented with 0-100% for every hour in the 24 hours range
	map<string,map<int,map<int,float>>> timeProbabilities;
    map<string,map<int,float>> timeThresholds;
    
    //Mode probabilities by activity type and spatial extent (city/region). Modes: "walk","bike","car","car_passenger","public_transport","other_mode"
    map<string,map<bool,map<string,float>>> modeProbabilities;
    
    //Work duration probabilities by gender
    map<string,map<map<string,int>,float>> workDurationProbabilities;	
	
	//Initialzation
	init{
		float initializationStartTime <- machine_time; //the initialization starts
		
		//Create the city outline
		cityOutline <- geometry(fileCityOutline);
		remove fileCityOutline from:self;
		
		//Create species
		do createRoads;
		do createIntersections;
		do createFacilities;
		do createCountingStations;
		do createPersons;
		
		//Import decision-making rules and create initial mobility schedules for persons
		do prepareProbabilities;
		do calculateFirstActivity;
		
		//Create the "trips" file
		save "self;gender;age;activityId;activityType;startingTime;endingTime;durationTime;travelTime;mode;speed;tripLength;tripCityShare;intersections;trip_geom;"to:tripsFileName type:"text" rewrite:false;
		
		write "duration of initialization: " + (machine_time - initializationStartTime)/1000; //initialization time
	}

	//Create "facility" species
	action createFacilities{
		create facility from: fileHomePlaces with:[facilityPopulation::int(read("residents"))]{
			facilityType <- "other_place";//"other_place" facilities are homes of persons
			if facilityPopulation=0{do die;}
		}
		create facility from: fileWorkPlaces with: [facilityPopulation::int(read("employees"))]{
			facilityType <- "work";
			if facilityPopulation=0{do die;}
		}
		create facility from: fileWorkPlaces with: [facilityPopulation::int(read("employees"))]{
			facilityType <- "business";
			if facilityPopulation=0{do die;}
		}
		create facility from: fileFacilities with:[facilityType::string(read("type"))]{
			if length(road overlapping(self))>0{
				location <- {location.x+0.000001,location.y,0.0}; // select nearby location, because GAMA generates an error when calculating routes from points that intersect link vertices of the graph
			}
		}
		
		remove fileFacilities from:self;
	}
	
	//Create "road" species.
	action createRoads{
		//The attributes of network file are characterized by direction: the "ft" is from-to direction, the "tf" is to-from direction. 
		loop link over:fileRoads{
			float safetyInd; //safety index
			float safetyInd_opposite; //safety index of opposite way
			int restrict; //restriction level, explained in the "calculateSafetyIndex" section
			int restrict_opposite; //restriction level of opposite way, explained in the "calculateSafetyIndex" section
			geometry geom; //link geometry

			//Calculate a safety index and geometry according to a link direction
			if int(link.attributes['oneway_ft']) = 1 and int(link.attributes['oneway_tf']) = 0{ //if a link has a single direction "FT"
				safetyInd <- calculateSafetyIndex(int(link.attributes['link_id']),int(link.attributes['brunnel']),string(link.attributes['basetype']),string(link.attributes['bic_inf_ft']),
													int(link.attributes['mit_vol_ft']),string(link.attributes['d_route_ft']),string(link.attributes['road_categ']),int(link.attributes['max_sp_ft']),
													int(link.attributes['ad_edge_ft']),string(link.attributes['parking_ft']),string(link.attributes['pavement']),int(link.attributes['width_lane']),
													int(link.attributes['grad_ft']),string(link.attributes['rails']),int(link.attributes['n_lanes_ft']),string(link.attributes['land_use']),
													int(link.attributes['restric_ft']));
				restrict<-int(link.attributes['restric_ft']);
				geom <- polyline(link.points);
			}else if int(link.attributes['oneway_ft']) = 0 and int(link.attributes['oneway_tf']) = 1{ //if a link has a single direction "TF"
				safetyInd <- calculateSafetyIndex(int(link.attributes['link_id']),int(link.attributes['brunnel']),string(link.attributes['basetype']),string(link.attributes['bic_inf_tf']),
													int(link.attributes['mit_vol_tf']),string(link.attributes['d_route_tf']),string(link.attributes['road_categ']),int(link.attributes['max_sp_tf']),
													int(link.attributes['ad_edge_tf']),string(link.attributes['parking_tf']),string(link.attributes['pavement']),int(link.attributes['width_lane']),
													int(link.attributes['grad_tf']),string(link.attributes['rails']),int(link.attributes['n_lanes_tf']),string(link.attributes['land_use']),
													int(link.attributes['restric_tf']));
				restrict<-int(link.attributes['restric_tf']);
				geom <- polyline(reverse(link.points)); //reverse a link geometry to have an opposite direction
			}else{
				//If a link has both  "FT" and "TF" directions
				safetyInd <- calculateSafetyIndex(int(link.attributes['link_id']),int(link.attributes['brunnel']),string(link.attributes['basetype']),string(link.attributes['bic_inf_ft']),
													int(link.attributes['mit_vol_ft']),string(link.attributes['d_route_ft']),string(link.attributes['road_categ']),int(link.attributes['max_sp_ft']),
													int(link.attributes['ad_edge_ft']),string(link.attributes['parking_ft']),string(link.attributes['pavement']),int(link.attributes['width_lane']),
													int(link.attributes['grad_ft']),string(link.attributes['rails']),int(link.attributes['n_lanes_ft']),string(link.attributes['land_use']),
													int(link.attributes['restric_ft']));
				restrict<-int(link.attributes['restric_ft']);
				geom <- polyline(link.points);
				
				safetyInd_opposite <- calculateSafetyIndex(int(link.attributes['link_id']),int(link.attributes['brunnel']),string(link.attributes['basetype']),string(link.attributes['bic_inf_tf']),
													int(link.attributes['mit_vol_tf']),string(link.attributes['d_route_tf']),string(link.attributes['road_categ']),int(link.attributes['max_sp_tf']),
													int(link.attributes['ad_edge_tf']),string(link.attributes['parking_tf']),string(link.attributes['pavement']),int(link.attributes['width_lane']),
													int(link.attributes['grad_tf']),string(link.attributes['rails']),int(link.attributes['n_lanes_tf']),string(link.attributes['land_use']),
													int(link.attributes['restric_tf']));
				restrict_opposite<-int(link.attributes['restric_tf']);
			}
			
			//Create roads
			create road number:1{
				id<-int(link.attributes['id']);
				safetyIndex<-safetyInd;
				weight<-(1+safetyInd)*5-4; //link weight based on a safety index
				restriction<-restrict;
				shape<-geom;
				
				//Create an opposite road if a link is bothways
				if safetyInd_opposite!=nil{	
					create road number:1{
						id<-int(link.attributes['id'])*-1; //assign a negative id
						restriction<-restrict_opposite;
						safetyIndex<-safetyInd_opposite;
						weight<-(1+safetyInd_opposite)*5-4;
						shape <- polyline(reverse(myself.shape.points)); //reverse a link geometry to have an opposite direction
						if restriction!=2{
							myself.oppositeRoad<-self; //assign a road as opposite to an original road
						}
					}
				}
			}
		}
		
		ask road{if restriction=2{do die;}} //delete links restricted for cycling and pushing
		
		//Calculate the network graph depending on the user-defined parameter of the routing algorithm for cyclists
		if routingAlgorithm<="safest path"{
    		cyclingWeights <- road as_map (each::(each.weight*each.shape.perimeter));
    	}else { //"shortest path"
    		cyclingWeights <- road as_map (each::each.shape.perimeter);
    	}
		perimeterWeights<- road as_map (each::each.shape.perimeter);
		theGraph <- directed(as_edge_graph(road) with_weights cyclingWeights);
		
		remove fileRoads from:self;
	}
	
	/* The network assessment model calculates a safety index for every road. The required road attributes are:
	 * brunnel - tunnel or bridge: "0"-no, "1"-yes
	 * baseType - type of lane usage: 
	 			  * 1-roadway, 2-bicycle path, 4-rail, 5-traffic island, 6-stairway, 7-side walk, 8-parking lane, 11-driving lane, 
	 			  * 12-waterway, 13-uphill, 14-right turn lane, 21-protected pedestrian crossing, 22-bicycle crossing, 
	 			  * 23-protected pedestrian and bicycle crossing, 24-tunnel, 25-bridge, 31-bike path with adjoining walkway, 
	 			  * 32-multipurpose lanes, 33-bicycle lanes, 34-busway, 35-bicycle lane against the one-way, 36-pedestrian and bicycle path
	 * bicycleInfrastructure - type of bicycle infrastructure:
	 						   * "bicycle_way" - physically separated bicycle lane, "bicycle_lane" - bicycle lane adjacent to motorized lane, 
	 						   * "mixed_way" - a lane for bicycles and motorized vehicles, "no" - a motorized lane, no bicycles allowed
	 * mitVolume - daily traffic volume of motorized vehicles per segment (24h)
	 * designatedRoute:
	 			  * "planning"- road segments where planning authorities want bicyclists to ride; usually not available in standard data sets, must be obtain in workshops etc.
	 			  * "national" - highest category of designated routes, often along major rivers (in Austria e.g. Tauernradweg, Donauradweg etc.)
				  * "regional" - designated routes with major, regional impact, often realized as thematic routes (in Salzburg e.g. Mozartradweg)
				  * "local " - designated routes within municipalities/towns, often sponsored by local businesses (in Salzburg e.g. Raiffeisenradweg)
				  * "no" - no designated routes or planning intents
	 * roadCategory:
	 			  * "primary" -  highest category of roads which are traversable by bicyclists (highways are excluded!). Mostly maintained by national/federal authorities and numbered (in Austria with prefix B),
				  * "secondary" - next highest category of roads. Mostly maintained by regional authorities and numbered (in Austria with prefix L). Within cities major roads which are not maintained by national/federal authorities should be of this category,
				  * "residential" - municipal roads which don’t belong to one of the 2 higher categories,
				  * "service" - all kinds of access and small connector roads where bicycles are permitted (e.g. Verbindungsweg, Zufahrt, Stichstraße etc.),
				  * "calmed" - roads with any kind of limited MIT access but bicycle permission (Begegnungszone, Wohnstraße, Anrainerstraßen, Wirtschaftswege etc.),
				  * "no_mit" - any roads with restricted MIT access but bicycle permission (pedestrian zone with bicycle permission, cycleway etc.),
				  * "path " - paths where cycling is either not permitted or not possible (although it is not explicitly restricted)
	 * maxSpeed - maximum speed allowed by regulations
	 * adjacentEdge - number of adjacent edges at the crossings
	 * parking - on-street parking: "yes","no"
	 * pavement: "asphalt" - paved road, "gravel" - road with compacted gravel, "soft" - uncompacted path with soft underground, "cobble" - road with cobble stones
	 * widthLane - lane width in meters
	 * gradient - gradient category according to classification for upslope and downhill:
	 			  * -1.5 % <“0”<1,5 %; 1,5 % <“1”< 3 %; 3 % <“2”< 6 %; 6 % <“3”< 12 %; “4” > 12 %; -1,5 % >“-1”> -3 %; -3 % >“-2”> -6 %; -6 % >“-3”> -12 %; “-4” < -12 %
	 * rails - railway on the road: "yes","no"
	 * numberLane - number of lanes
	 * landuse:
	 			  * "green" - areas that are not sealed and are “green” (open meadows, wood, pastures, parks etc.) or in “natural” condition (incl. water bodies etc.),
				  * "residential" - areas that are loosely covered with buildings (small towns and villages, single-family houses etc.),
				  * "built" - areas that are densely covered with buildings without/with little green spaces (cities, apartment buildings, multi-story buildings etc.),
				  * "commercial" - areas that are mainly covered by large commercial buildings (business parks etc.)
	 * oneway - availability of ways in one or both directions. If both directions are "0", then both ways. If one of directions is "0" and another one is "1", then one way
	 * restriction: "0" - not restricted, "1" - restricted for motorized vehicles, allowed to push bike, "2" - restricted for every type of mode
	 */
	float calculateSafetyIndex(int linkId,int brunnel,string baseType,string bicycleInfrastructure,int mitVolume,string designatedRoute,string roadCategory,int maxSpeed,int adjacentEdge,
							   string parking,string pavement,int widthLane,int gradient,string rails,int numberLane,string landuse,int restriction){
		list<float>indicators;
		list<float>weights<- [
			bicycleInfrastructureWeight,mitVolumeWeight,designatedRouteWeight,roadCategoryWeight,maxSpeedWeight,adjacentEdgeWeight,
			parkingWeight,pavementWeight,widthLaneWeight,gradientWeight,railsWeight,numberLaneWeight,landuseWeight
		];
		
		//Calculate inidicators
		switch bicycleInfrastructure{
			match "bicycle_way"{add 0.0 to: indicators;}
			match "mixed_way"{add 0.1 to: indicators;}
			match "bicycle_lane"{add 0.25 to: indicators;}
			match "bus_lane"{add 0.25 to: indicators;}
			match "shared_lane"{add 0.5 to: indicators;}
			match "undefined"{add 0.8 to: indicators;}
			match "no"{add 1.0 to: indicators;}
			default{add -9999.0 to: indicators;}
		}
		
		if mitVolume>=0{
			if mitVolume = 0 {add 0.0 to: indicators;} else
       	 	if mitVolume < 500 {add 0.05 to: indicators;} else
       	 	if mitVolume < 2500 {add 0.25 to: indicators;} else
            if mitVolume < 7500 {add 0.5 to: indicators;} else
            if mitVolume < 15000 {add 0.75 to: indicators;} else
            if mitVolume < 25000 {add 0.85 to: indicators;} else
            if mitVolume >= 25000 {add 1 to: indicators;}
		} else {add -9999.0 to: indicators;}
		
		switch designatedRoute{
			match "planning"{add 0.0 to: indicators;}
			match "national"{add 0.1 to: indicators;}
			match "regional"{add 0.15 to: indicators;}
			match "local"{add 0.2 to: indicators;}
			match "no"{add 1.0 to: indicators;}
			default{add -9999.0 to: indicators;}
		}
		
		switch roadCategory{
			match "primary"{add 1.0 to: indicators;}
			match "secondary"{add 0.8 to: indicators;}
			match "residential"{add 0.2 to: indicators;}
			match "service"{add 0.15 to: indicators;}
			match "calmed"{add 0.1 to: indicators;}
			match "no_mit"{add 0.0 to: indicators;}
			match "path"{add 1.0 to: indicators;}
			default{add -9999.0 to: indicators;}
		}
		
		if maxSpeed>= 0{
			if maxSpeed= 0 {add 0.0 to: indicators;} else 
			if maxSpeed<30 {add 0.1 to: indicators;} else
			if maxSpeed<50 {add 0.15 to: indicators;} else
			if maxSpeed<60 {add 0.4 to: indicators;} else
			if maxSpeed<70 {add 0.6 to: indicators;} else
			if maxSpeed<80 {add 0.7 to: indicators;} else
			if maxSpeed<100 {add 0.8 to: indicators;} else
			if maxSpeed>=100 {add 1.0 to: indicators;}
		} else {add -9999.0 to: indicators;}
		
		if adjacentEdge >= 0{
			if adjacentEdge <= 2 {add 0.0 to: indicators;} else
            if adjacentEdge = 3 {add -9999.0 to: indicators;} else
            if adjacentEdge = 4 {add -9999.0 to: indicators;} else
            if adjacentEdge = 5 {add -9999.0 to: indicators;} else
           	if adjacentEdge = 6 {add -9999.0 to: indicators;} else
            if adjacentEdge >= 7 {add 1 to: indicators;}
		} else {add -9999.0 to: indicators;}
            
        switch parking {
        	match "yes"{add 1.0 to: indicators;}
        	match "no"{add 0.0 to: indicators;}
        	default {add -9999.0 to: indicators;}
        }
        
		switch pavement{
			match "asphalt"{add 0.0 to: indicators;}
			match "gravel"{add 0.25 to: indicators;}
			match "soft"{add 0.6 to: indicators;}
			match "cobble"{add 1.0 to: indicators;}
			default{add -9999.0 to: indicators;}
		}
		
		if widthLane >= 0{
			if widthLane>5 {add 0.0 to: indicators;} else 
			if widthLane>4 {add 0.1 to: indicators;} else
			if widthLane>3 {add 0.15 to: indicators;} else
			if widthLane>2 {add 0.5 to: indicators;} else
			if widthLane<=2 {add 1.0 to: indicators;}
		} else {add -9999.0 to: indicators;}
		
		switch gradient{
			match 4{add 1.0 to: indicators;}
			match 3{add 0.75 to: indicators;}
			match 2{add 0.6 to: indicators;}
			match 1{add 0.5 to: indicators;}
			match 0{add 0.1 to: indicators;}
			match -1{add 0.0 to: indicators;}
			match -2{add 0.05 to: indicators;}
			match -3{add 0.65 to: indicators;}
			match -4{add 1.0 to: indicators;}
			default{add -9999.0 to: indicators;}
		}
		switch rails {
        	match "yes"{add 1.0 to: indicators;}
        	match "no"{add 0.0 to: indicators;}
        	default {add -9999.0 to: indicators;}
        }
		
		if numberLane>=0{
			if numberLane<= 1 {add 0.0 to: indicators;} else 
			if numberLane<= 2 {add 0.5 to: indicators;} else
			if numberLane<= 3 {add 0.8 to: indicators;} else
			if numberLane<= 4 {add 0.9 to: indicators;} else
			if numberLane> 4 {add 1.0 to: indicators;} 
		} else {add -9999.0 to: indicators;}
		
		switch landuse {
        	match "green"{add 0.0 to: indicators;}
        	match "residential"{add 0.25 to: indicators;}
        	match "built_area"{add 0.8 to: indicators;}
        	match "commercial"{add 1.0 to: indicators;}
        	default {add -9999.0 to: indicators;}
        }
		
		//Adjust weights
		if (gradient=4 or gradient=3 or gradient=-3 or gradient=-4)
		and	(pavement="gravel" or pavement ="soft" or pavement="cobble"){
			weights[7]<-pavementAdjusted;
			weights[9]<-gradientAdjusted;
			float sum<-0.0;
			loop weightIndex from: 0 to: length (weights) - 1 {
				if weightIndex !=7 and weightIndex!=9{
					sum<- sum+weights[weightIndex];
				}
			}
			loop weightIndex1 from: 0 to: length (weights) - 1 {
				if weightIndex1 !=7 and weightIndex1 !=9{
					weights[weightIndex1]<- (weights[weightIndex1]/sum)*(1-weights[7]-weights[9]);
				}
			}
		}
		
		//Calculate a safety index
		float sum1<-0.0;
		loop indicatorIndex from: 0 to: length (indicators) - 1 {
			if indicators[indicatorIndex] !=-9999{
				sum1 <- sum1+weights[indicatorIndex];
			}
		}
		
		loop indicatorIndex1 from: 0 to: length (indicators) - 1 {
			if indicators[indicatorIndex1] !=-9999{
				weights[indicatorIndex1]<- weights[indicatorIndex1]/sum1;
			} else{
				weights[indicatorIndex1]<- 0.0;
			}
		}
			
		float safetyIndex <-0.0;
		loop indicatorIndex2 from: 0 to: length (indicators) - 1 {
			safetyIndex <- safetyIndex + indicators[indicatorIndex2]*weights[indicatorIndex2];
		}
		
		//Convert a basetype attribute
		container baseTypeList;
		if baseType!=''{
			baseTypeList<- baseType split_with ";";
			
			loop baseTypeIndex from: 0 to: length (baseTypeList) - 1 {
				if baseTypeList[baseTypeIndex] ="*"{
					baseTypeList[baseTypeIndex]<-"None";
				}else {
					baseTypeList[baseTypeIndex]<-int(baseTypeList[baseTypeIndex]);
				}
			}
		}
		
		//Weight a safety index depending on indicators
		if linkId= 901425318 { //Staatsbrücke bridge
			safetyIndex <- bridgeValue+1;
		} else if baseType !='' and baseTypeList contains 6{ //Stairs
		 	safetyIndex<- pushValue*1.5;
		} else if (gradient > 1 or gradient < -1) and restriction = 1{ //Slope with push requirement
		 	safetyIndex <- pushValue+abs(gradient)/1.5;
		} else if brunnel=1 and restriction =0{ //Bridges
		 	safetyIndex <- bridgeValue;
		} else if brunnel=0 and restriction =1{
		 	safetyIndex <- pushValue;
		} else if brunnel =1 and restriction = 1{ //Bridges with push requirement
		 	safetyIndex <- bridgeValue + (pushValue/1.5);
		}
		
		return safetyIndex with_precision 4;
	}
	
	//Create "intersection" species
	action createIntersections{
		create intersection from: fileIntersections;
	}

	//Create "counting stations" species
	action createCountingStations{
		create countingStation from: fileCountingStations with:[stationName::string(read("stat_name"))]{	
			//import the observed counts data to each counting station for visualization	
			int stationColumn;
			switch stationName{
				match "rudolfskai" {stationColumn<-1;}
				match "wallnergasse" {stationColumn<-2;}
				match "elisabethkai" {stationColumn<-3;}
				match "giselakai" {stationColumn<-4;}
				match "schanzlgasse" {stationColumn<-5;}
				match "kaufmann_steg" {stationColumn<-6;}
				match "ischlerbahntrasse" {stationColumn<-7;}
				match "alterbach" {stationColumn<-8;}
				match "moosbrucker_weg" {stationColumn<-9;}
			}
			
			loop hourRow from:0 to:countsMatrix.rows-1{
				add int(countsMatrix[stationColumn,hourRow]) at:int(countsMatrix[0,hourRow]) to:self.observedCounts;
			}
		}
		
		remove fileCountingStations from:self;
		remove countsMatrix from:self;
	}
		
	//Create "person" species
	action createPersons {
		float time_createPersons <- machine_time;
		list<int> femaleByAge; //the list of female population by an age group with "5 years" increment
		list<int> maleByAge; //the list of male population by an age group with "5 years" increment
		list<person> createdPersons; //the list of created persons at each residential cell
		int ageMin; //age group minimum limit
		int ageMax; //age group maximum limit
		
		loop home over:fileHomePlaces{//loop the cells of the residential data
			//Import the number of residents by an age group for every cell
			femaleByAge<-[
				int(home.attributes["f_below_5"]),int(home.attributes["f_5_9"]),int(home.attributes["f_10_14"]),int(home.attributes["f_15_19"]),
				int(home.attributes["f_20_24"]),int(home.attributes["f_25_29"]),int(home.attributes["f_30_34"]),int(home.attributes["f_35_39"]),
				int(home.attributes["f_40_44"]),int(home.attributes["f_45_49"]),int(home.attributes["f_50_54"]),int(home.attributes["f_55_59"]),
				int(home.attributes["f_60_64"]),int(home.attributes["f_65_69"]),int(home.attributes["f_70_74"]),int(home.attributes["f_75_79"]),
				int(home.attributes["f_80_84"]),int(home.attributes["f_85_89"]),int(home.attributes["f_90_94"]),int(home.attributes["f_95_99"]),
				int(home.attributes["f_over_100"])];
			maleByAge<-[
				int(home.attributes["m_below_5"]),int(home.attributes["m_5_9"]),int(home.attributes["m_10_14"]),int(home.attributes["m_15_19"]),
				int(home.attributes["m_20_24"]),int(home.attributes["m_25_29"]),int(home.attributes["m_30_34"]),int(home.attributes["m_35_39"]),
				int(home.attributes["m_40_44"]),int(home.attributes["m_45_49"]),int(home.attributes["m_50_54"]),int(home.attributes["m_55_59"]),
				int(home.attributes["m_60_64"]),int(home.attributes["m_65_69"]),int(home.attributes["m_70_74"]),int(home.attributes["m_75_79"]),
				int(home.attributes["m_80_84"]),int(home.attributes["m_85_89"]),int(home.attributes["m_90_94"]),int(home.attributes["m_95_99"]),
				int(home.attributes["m_over_100"])];
			createdPersons<-[];

			//Create persons within a cell
			ageMin<-0;//the first age group is 0-4. These variables are updated with an increment of 5 years.
			ageMax<-4;
			int ageGroupCounter<-0;
			loop while:ageGroupCounter<length(femaleByAge){
				//Create female persons
				create person number:femaleByAge[ageGroupCounter]{
					age<-rnd(ageMin,ageMax); //randomly assign an age between min and max age values
					gender<-"female";
					homeLocation <- any_location_in(polygon(home.points)); //randomly assign a home location within a cell geometry
					add self to: createdPersons;
				}
				
				//Create male persons
				create person number:maleByAge[ageGroupCounter]{
					age<-rnd(ageMin,ageMax); //randomly assign an age between min and max age values
					gender<-"male";
					homeLocation <- any_location_in(polygon(home.points)); //randomly assign a home location within a cell geometry
					add self to: createdPersons;
				}
				
				//Increment an age group
				ageMin<-ageMin+5;
				ageMax<-ageMax+5;
				ageGroupCounter<-ageGroupCounter+1;
			}

			//Calculate employment statuses
			do assignEmploymentStatus("below_15",int(home.attributes["m_below_15"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "male" and each.age >= 0 and each.age <= 14)));
			do assignEmploymentStatus("below_15",int(home.attributes["f_below_15"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "female" and each.age >= 0 and each.age <= 14)));
			do assignEmploymentStatus("pensioner",int(home.attributes["m_pension"]),reverse(createdPersons where(each.employmentStatus = "" and each.gender= "male") sort_by (each.age)));
			do assignEmploymentStatus("pensioner",int(home.attributes["f_pension"]),reverse(createdPersons where(each.employmentStatus = "" and each.gender= "female") sort_by (each.age)));
			do assignEmploymentStatus("pupils_students_over_15",int(home.attributes["m_students"]),createdPersons where (each.employmentStatus = "" and each.gender = "male" and each.age >= 15) sort_by(each.age));
			do assignEmploymentStatus("pupils_students_over_15",int(home.attributes["f_students"]),createdPersons where (each.employmentStatus = "" and each.gender = "female" and each.age >= 15) sort_by(each.age));
			do assignEmploymentStatus("employed",int(home.attributes["m_employed"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "male" and each.age >= 15)));
			do assignEmploymentStatus("employed",int(home.attributes["f_employed"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "female" and each.age >= 15)));
			do assignEmploymentStatus("unemployed",int(home.attributes["m_unemploy"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "male" and each.age >= 15)));
			do assignEmploymentStatus("unemployed",int(home.attributes["f_unemploy"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "female" and each.age >= 15)));
			do assignEmploymentStatus("inactive",int(home.attributes["m_inactive"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "male" and each.age >= 15)));
			do assignEmploymentStatus("inactive",int(home.attributes["f_inactive"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "female" and each.age >= 15)));
			do assignEmploymentStatus("undefined",int(home.attributes["m_emp_unk"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "male" and each.age >= 15)));
			do assignEmploymentStatus("undefined",int(home.attributes["f_emp_unk"]),shuffle(createdPersons where (each.employmentStatus = "" and each.gender = "female" and each.age >= 15)));
			
			//Remove persons under 6 years old from the simulation, because of their inability to carry out activities and travel on their own. Remove persons whose employment status is unknown.
			ask createdPersons where(each.age<6 or each.employmentStatus ="undefined"){
				remove self from:createdPersons; do die;
			}
			
			//Update employment statuses by assigning education statuses (pupil, student). 
			//Pupils and students over 15 can be registered as "employed", thats why some of "employed" persons will be reassigned with "pupil"/"student" statuses, persons "below_15" will be reassigned as "pupils". 
			do assignEmploymentStatus("pupil",int(home.attributes["pupils"]),reverse(createdPersons where (each.employmentStatus = "below_15") sort_by (each.age))+
													   createdPersons where (each.employmentStatus = "pupils_students_over_15") sort_by (each.age) + 
													   createdPersons where (each.employmentStatus = "employed") sort_by (each.age)
			);
			do assignEmploymentStatus("student",int(home.attributes["students"]),createdPersons where (each.employmentStatus = "pupils_students_over_15" or each.employmentStatus = "employed") sort_by (each.age));
		}
		
		//Remove persons from the simulation, whose education statuses were not defined due to unknown values
		ask person where(each.employmentStatus="below_15" or each.employmentStatus="pupils_students_over_15"){do die;}
		
		remove fileHomePlaces from:self;
		write "Persons are created: " + person count(true) + ". Execution time: "+ (machine_time - time_createPersons)/1000+" sec";		
	}
	
	//Assign an employment status. "emStName" - employment status type, "numberEmpSt" - required number of people by employment status, "the_persons" - suitable persons
	action assignEmploymentStatus(string empStName,int numberEmpSt,list<person>the_persons){		
		person rndPerson;
		loop while:numberEmpSt!=0{
			rndPerson <- first(the_persons);
			rndPerson.employmentStatus <- empStName;
			the_persons<-the_persons-rndPerson;
			numberEmpSt<-numberEmpSt-1;
		}
	}
	
	//Prepare probability distributions of activity types, departure times and modes
	action prepareProbabilities{
		//Calculate the activity type probabilities depending on employment status and activity position
		//The matrix columns (1-12) represent activity types. The rows (0-7) represent activity positions
		int persons_total <- length(person); //total number of the population
		loop emp_status over: ["employed","unemployed","inactive","pensioner","pupil","student"]{ //loop through employment statuses
			map<int,map<string,float>> probabilitiesById; //list of probabilities by activity position
			loop actPosRow from:0 to:activityMatrix.rows-1{ //loop through the rows of activity positions
				map<string,float> probabilities; //list of probabilities by activity type
				//Import probabilities for the total population from the file
				loop actTypeColumn from: 0 to: activityMatrix.columns-1{ //loop through the columns of activity type
					switch actTypeColumn{ //add probability values to the "probabilities" list
						match 0{add float(activityMatrix[actTypeColumn,actPosRow]) at: "home" to: probabilities;}
						match 1{add float(activityMatrix[actTypeColumn,actPosRow]) at: "other_place" to: probabilities;}
						match 2{add float(activityMatrix[actTypeColumn,actPosRow]) at: "work" to: probabilities;}
						match 3{add float(activityMatrix[actTypeColumn,actPosRow]) at: "business" to: probabilities;}
						match 4{
							add float(activityMatrix[actTypeColumn,actPosRow]) at: "school" to: probabilities;
							add float(activityMatrix[actTypeColumn,actPosRow]) at: "university" to: probabilities;
						} 
						match 5{add float(activityMatrix[actTypeColumn,actPosRow]) at: "shop" to: probabilities;}
						match 6{add float(activityMatrix[actTypeColumn,actPosRow]) at: "authority" to: probabilities;}
						match 7{add float(activityMatrix[actTypeColumn,actPosRow]) at: "doctor" to: probabilities;}
						match 8{add float(activityMatrix[actTypeColumn,actPosRow]) at: "recreation" to: probabilities;}
						match 9{add float(activityMatrix[actTypeColumn,actPosRow]) at: "bringing" to: probabilities;}
						match 10{add float(activityMatrix[actTypeColumn,actPosRow]) at: "none" to: probabilities;}
					}
				}
				//Recalculate probabilities depending on employment status
				float unessential_probabilities <- 100.0-probabilities["work"]-probabilities["business"]-probabilities["school"]; //summ of the probabilities of non-utalititarian activities
				switch emp_status{
					match "employed"{
						float new_work_probability <- persons_total*probabilities["work"]/length(person where (each.employmentStatus=emp_status));//new "work" probability for the amount of employed persons
						float new_business_probability <- persons_total*probabilities["business"]/length(person where (each.employmentStatus=emp_status));//new "business" probability for the amount of employed persons
						if new_work_probability+new_business_probability>100.0{ //proportionalize the "work" and "business" probabilities to be under 100 in total
							new_work_probability <- new_work_probability*100.0/(new_work_probability+new_business_probability);
							new_business_probability <- 100.0-new_work_probability;
						}
						loop activity over:probabilities.keys{
							switch activity{
								match "work"{probabilities[activity]<-new_work_probability;}
								match "business"{probabilities[activity]<-new_business_probability;}
								match "school"{probabilities[activity]<-0.0;}
								match "university"{probabilities[activity]<-0.0;}
								default{probabilities[activity]<-(100.0-new_work_probability-new_business_probability)*probabilities[activity]/unessential_probabilities;}
							}
						}
					}
					match "pupil"{
						float new_school_probability <- persons_total*probabilities["school"]/length(person where (each.employmentStatus="pupil" or each.employmentStatus="student"));//new "school" probability for the amount of pupils and students
						loop activity over:probabilities.keys{
							switch activity{
								match "work"{probabilities[activity]<-0.0;}
								match "business"{probabilities[activity]<-0.0;}
								match "school"{probabilities[activity]<-new_school_probability;}
								match "university"{probabilities[activity]<-0.0;}
								default{probabilities[activity]<-(100.0-new_school_probability)*probabilities[activity]/unessential_probabilities;}
							}
						}
					}
					match "student"{
						float new_university_probability <- persons_total*probabilities["university"]/length(person where (each.employmentStatus="pupil" or each.employmentStatus="student"));//new "university" probability for the amount of pupils and students
						loop activity over:probabilities.keys{
							switch activity{
								match "work"{probabilities[activity]<-0.0;}
								match "business"{probabilities[activity]<-0.0;}
								match "school"{probabilities[activity]<-0.0;}
								match "university"{probabilities[activity]<-new_university_probability;}
								default{probabilities[activity]<-(100.0-new_university_probability)*probabilities[activity]/unessential_probabilities;}
							}
						}
					}
					default{
						loop activity over:probabilities.keys{
							switch activity{
								match "work"{probabilities[activity]<-0.0;}
								match "business"{probabilities[activity]<-0.0;}
								match "school"{probabilities[activity]<-0.0;}
								match "university"{probabilities[activity]<-0.0;}
								default{probabilities[activity]<-100.0*probabilities[activity]/unessential_probabilities;}
							}
						}
					}
				}
				add probabilities at:actPosRow to:probabilitiesById; //add the "probabilities" to the "probabilitiesById" list
			}
			add probabilitiesById at:emp_status to:activityProbabilities; //add the "probabilitiesById" to the final "activityProbabilities" list
		}
		remove activityMatrix from:self;
		
		//Calculate accumulative departure time probabilities (0-100%). The matrix columns (2-26) represent 24 hours. The rows (1-64) represent activity type and position in activity chain. 
		int activityCounter<-0; //variable for looping through activity types
		loop actTypeRow from:0 to:8{ //loop through rows of activity types
			map<int,map<int,float>> probabilitiesByPosition; //list of probabilities by activity position
			map<int,float> thresholdsByPosition; //list of threshold probabilities by activity position
			loop actPositionRow from:0+activityCounter to: 6+activityCounter{ //loop through rows of activity positions
				float newTimeProbability; //accumulative probability from 0 to 100%
				map<int,float>probabilities; //list of prababilities by hour
				loop hourColumn from: 2 to: timeMatrix.columns-1{ //loop through hours
					if float(timeMatrix[hourColumn,actPositionRow])>0.0{
						newTimeProbability <- newTimeProbability+float(timeMatrix[hourColumn,actPositionRow]);
						add newTimeProbability at:hourColumn-1 to:probabilities; //add the probability value to the "probabilities" list
					}
				}
				add probabilities at: actPositionRow-activityCounter+1 to: probabilitiesByPosition; //add the "probabilities" to the "probabilitiesByPosition" list
				add 0.0 at: actPositionRow-activityCounter to:thresholdsByPosition; //set 0.0 for all thresholds. They will be updated during the simulation
			}
			switch actTypeRow{ //add the "probabilitiesByPosition" to the final "timeProbabilities" list and the "thresholdsByPosition" to the final "timeThresholds" list
				match 0{add probabilitiesByPosition at: "home" to:timeProbabilities; add thresholdsByPosition at: "home" to:timeThresholds;}
				match 1{add probabilitiesByPosition at: "other_place" to:timeProbabilities;add thresholdsByPosition at: "other_place" to:timeThresholds;}
				match 2{add probabilitiesByPosition at: "work" to:timeProbabilities;add thresholdsByPosition at: "work" to:timeThresholds;}
				match 3{add probabilitiesByPosition at: "business" to:timeProbabilities;add thresholdsByPosition at: "business" to:timeThresholds;}
				match 4{add probabilitiesByPosition at: "shop" to:timeProbabilities;add thresholdsByPosition at: "shop" to:timeThresholds;}
				match 5{add probabilitiesByPosition at: "authority" to:timeProbabilities;add thresholdsByPosition at: "authority" to:timeThresholds;}
				match 6{add probabilitiesByPosition at: "doctor" to:timeProbabilities;add thresholdsByPosition at: "doctor" to:timeThresholds;}
				match 7{add probabilitiesByPosition at: "recreation" to:timeProbabilities;add thresholdsByPosition at: "recreation" to:timeThresholds;}
				match 8{add probabilitiesByPosition at: "bringing" to:timeProbabilities;add thresholdsByPosition at: "bringing" to:timeThresholds;}
			}
			activityCounter <- activityCounter+7; //update the activityCounter
		}	
		remove timeMatrix from:self;
		
		//Calculate mode type probabilities. The matrix columns (2-7) represent mode. The rows (0-21) represent activity type and extent (city/region).
		activityCounter<-0; //variable for looping through activity types		
		loop actTypeRow from:0 to:10{ //loop through the rows of activity types
			map<bool,map<string,float>> probabilitiesByExtend; //list of probabilities by spatial extent
			loop extendRow from:0+activityCounter to: 1+activityCounter{ //loop through through the rows of spatial extents
				float newModeProbability; //accumulative probability from 0 to 100%
				map<string,float>probabilities; //list of probabilities by mode
				loop modeColumn from: 2 to: modeMatrix.columns-1{ //loop through the columns of modes
					if float(modeMatrix[modeColumn,extendRow])>0.0{
						newModeProbability <- newModeProbability+float(modeMatrix[modeColumn,extendRow]);
						switch modeColumn{ //add probability values to the "probabilities" list
							match 2{add newModeProbability at:"walk" to:probabilities;}
							match 3{add newModeProbability at:"bike" to:probabilities;}
							match 4{add newModeProbability at:"car" to:probabilities;}
							match 5{add newModeProbability at:"car_passenger" to:probabilities;}
							match 6{add newModeProbability at:"public_transport" to:probabilities;}
							match 7{add newModeProbability at:"other_mode" to:probabilities;}						
						}
					}
				}
				if last(probabilities)<100.0{probabilities[probabilities index_of last(probabilities)] <- 100.0;} //set a sharp (100.0) limit for the last probability in the list
				switch extendRow-activityCounter{ //add the "probabilities" to the "probabilitiesByExtend" list
					match 0{add probabilities at: true to: probabilitiesByExtend;}
					match 1{add probabilities at: false to: probabilitiesByExtend;}
				}
			}
			switch actTypeRow{ //add the "probabilitiesByExtend" to the final "modeProbabilities" list
				match 0{add probabilitiesByExtend at: "home" to:modeProbabilities;}
				match 1{add probabilitiesByExtend at: "other_place" to:modeProbabilities;}
				match 2{add probabilitiesByExtend at: "work" to:modeProbabilities;}
				match 3{add probabilitiesByExtend at: "business" to:modeProbabilities;}
				match 4{add probabilitiesByExtend at: "school" to:modeProbabilities;}
				match 5{add probabilitiesByExtend at: "university" to:modeProbabilities;}
				match 6{add probabilitiesByExtend at: "shop" to:modeProbabilities;}
				match 7{add probabilitiesByExtend at: "authority" to:modeProbabilities;}
				match 8{add probabilitiesByExtend at: "doctor" to:modeProbabilities;}
				match 9{add probabilitiesByExtend at: "recreation" to:modeProbabilities;}
				match 10{add probabilitiesByExtend at: "bringing" to:modeProbabilities;}
			}
			activityCounter <- activityCounter+2;//update the activityCounter variable
		}
		remove modeMatrix from:self;
		
		//Calculate accumulative probabilities of duration of work activity. The matrix columns (2,3) represent gender. The columns (1,2) represent min/max working hours. The rows represent probabilities by gender and working hours.
		loop theGenderCol from:2 to:3{ //loop through the columns of gender
			float newDurationProbability; //accumulative probability from 0 to 100%
			map<map<string,int>,float> probabilities; //list of probabilities by working hours
			loop theRows from:0 to:durationMatrix.rows-1{ //loop through the rows of working hours
				map<string,int> workingHours; //min/max working hours in minutes per day (initial values are in hours per week)
				add int(durationMatrix[0,theRows])/5*60 at:"min" to:workingHours;
				add int(durationMatrix[1,theRows])/5*60 at:"max" to:workingHours;
				newDurationProbability <- newDurationProbability+float(durationMatrix[theGenderCol,theRows]); //accumulative probability from 0 to 100%
				add newDurationProbability at: workingHours to:probabilities; //add probability values to the "probabilities" list
			}
			if last(probabilities)<100.0{probabilities[probabilities index_of last(probabilities)] <- 100.0;} //set a sharp (100.0) limit for the last probability in the list
			switch theGenderCol{ //add the "probabilities" to the final "workDurationProbabilities" list
				match 2{add probabilities at:"male" to:workDurationProbabilities;}
				match 3{add probabilities at:"female" to:workDurationProbabilities;}
			}
		}
		remove durationMatrix from:self;
	}
	
	//Calculate initial travel schedules
	action calculateFirstActivity{
		ask person{
			//Locate a person at an initial activity
			activityId<-0;
			activityType <- calculateActivityType();
			location <- calculateTarget();
			
			//Calculate the next activity
			activityId <- activityId+1;
			activityType <- calculateActivityType();
			startingTime <- lastActivity=false ? calculateStartingTime() : 0;
			durationTime <- lastActivity=false ? calculateDurationTime() : 0;
			endingTime<-9999; //cannot use null value abbreviation "nil", because it equals 0 for int
			mode <- calculateMode();
			sourceLocation <- location;
			targetLocation <- lastActivity=false ? calculateTarget() : nil;
			if lastActivity=true{
				if location=homeLocation{
					do die;
				}else{
					activityType <- "home";
					startingTime <- cycle;
					targetLocation <- homeLocation;
				}
			}
		}
	}
	
	//The simulation starts
	reflex startSimulation when:cycle = 0{
		simulationStartTime <- machine_time;
	}
	
	//Update starting time probabilities with time thresholds. Persons can depart anytime from next hour
	reflex updateTimeThresholds when:every(60#cycle){
		loop activityT over:timeProbabilities.keys{
			loop activityP over:timeProbabilities[activityT].keys{
				if timeProbabilities[activityT][activityP][int(cycle/60)+1]!=nil{
					timeThresholds[activityT][activityP]<-timeProbabilities[activityT][activityP][int(cycle/60)+1];
				}	
				timeProbabilities[activityT][activityP]>-timeProbabilities[activityT][activityP][int(cycle/60)+1];
			}
		}
	}
	
	//Save moving cyclists by activity type every "activeCylistsTimeInterval" to the "active_cyclists" file
	reflex saveActiveCyclists when: every(activeCylistsTimeInterval#cycle){
		save[
			cycle,
			person count (each.status = "moving"),
			person count (each.status = "moving" and each.activityType="home"),
			person count (each.status = "moving" and each.activityType="work"),
			person count (each.status = "moving" and each.activityType="business"),
			person count (each.status = "moving" and each.activityType="school"),
			person count (each.status = "moving" and each.activityType="university"),
			person count (each.status = "moving" and each.activityType="authority"),
			person count (each.status = "moving" and each.activityType="doctor"),
			person count (each.status = "moving" and each.activityType="recreation"),
			person count (each.status = "moving" and each.activityType="shop"),
			person count (each.status = "moving" and each.activityType="bringing"),
			person count (each.status = "moving" and each.activityType="other_place")
		] to:activeCyclistsFileName type:csv rewrite:false;
	}
	
	//Save the heatmap with registered cyclists on the network by hour
	reflex saveHeatmap when:cycle = 1441{
		save road where(each.id >= 0) to: heatmapFileName type:"shp" crs:"EPSG:32633" rewrite:true attributes:[
			"id"::id,
			"safetyIndex"::safetyIndex,
			"cyclistsByIntervalInMin"::cyclistsByInterval,
			"cyclists"::cyclistsTotal
		];
	}

	//The simulation stops at 24:00
	reflex stopSimulation when: cycle = 1441{
		write "Total simulation time: " + (machine_time - simulationStartTime)/1000/60 + " min";
		do pause;
	}
}

//////////////////////////////////////////////////////////////////////////////SPECIES DECLARATION///////////////////////////////////////////////////////////////////////////////

/* Person species represent travelling objects that carry out activities
 * 1) The activity assignment is based on probabilities and assumptions about activity type, departure and duration times, mode, speed,
 * min/max travelling distance restrictions and target location
 * 2) Persons on bicycles that traverse city outline start to move at starting times. Other persons are teleported to target location at starting times.
 * 3) A movement ends at target location
 * 4) An activity continues until a duration time is over
 * 5) A next activity assignment occurs at an ending time of current activity in an iterative manner until the last activity*/
species person skills:[moving] {
	int age; //0-104
	string gender; //"male" and "female"
	string employmentStatus<-""; //"below_15", "pupil", "employed_pupil", "student", "employed_student","employed", "unemployed", "pensioner","inactive"(economically inactive, not registered as unemployed),"undefined"
	point homeLocation; //home location
    string status <- "staying"; //"staying" or "moving"
    
    int activityId; //every activity gets the ordinal number in a sequence (chain) of performed activities
    string activityType; //"home","work","business","school","university","shop","authority","doctor","recreation","bringing"(bringing children to kindergarden or children and old persons to hospital), "other_place"(any place else)
    bool lastActivity <- false; //"true" if the activity is the last one in the simulation
    int startingTime; //time to start travelling, in min
    int endingTime; //time to stop the activity, in min
    int durationTime; //time to spend at the activity location, in min
    string mode<-""; //transport mode: "walk","bike","car","car_passenger","public_transport","other_mode"
    float minDistance <-0.00; //minimum allowed distance to travel with the mode, in meters
    float maxDistance<-1000000.00; //maximum allowed distance to travel with the mode, in meters. Default value is 1000000.00 for "car", "car_passenger", "public_transport", "other_mode"
    point sourceLocation; //departure location
    point targetLocation; //target location
	
    aspect base {
        draw triangle(20) depth:rnd(2) color: #white; //person shape
    }
	
	//Calculate a next activity
	reflex calculateActivity when:cycle = endingTime{ 
		endingTime <- 9999;
		activityId <- activityId+1;
		activityType <- calculateActivityType();
		startingTime <- lastActivity=false ? calculateStartingTime() : 0;
		durationTime <- lastActivity=false ? calculateDurationTime() : 0;
		mode <- location=homeLocation ? calculateMode() : mode; //mode change is possible only at home
		sourceLocation <- location;
		targetLocation <- lastActivity=false ? calculateTarget() : nil;
		if lastActivity=true{ //if a selected activity is the last one, a person travels home or leaves the simulation world
			if location=homeLocation{
				do die;
			}else{
				activityType <- "home";
				startingTime <- cycle;
				targetLocation <- homeLocation;
			}
		}
	}
    
    //Calculate an activity type
	string calculateActivityType{
		//Calculate a probability distribution from 0.0% to 100.0%
		map<string,float>myActivityProbabilities <- copy(activityProbabilities[employmentStatus][activityId]);
		myActivityProbabilities[activityType]<-0.0;//a probability of a recent activity is excluded from probabilities
		float newActivityProbability;
		float probabilitiesSum <- sum(myActivityProbabilities);
		loop index over: myActivityProbabilities.keys {
			newActivityProbability <- newActivityProbability+myActivityProbabilities[index]*100/probabilitiesSum;
			myActivityProbabilities[index]<- newActivityProbability;
		}
		
		//Calculate an activity type according to a probability distribution
		float rndNumberActType <- rnd(last(myActivityProbabilities));
		switch rndNumberActType{
			match_between[0.0,myActivityProbabilities["home"]]{return "home";break;}
			match_between[myActivityProbabilities["home"],myActivityProbabilities["other_place"]]{return "other_place";break;}
			match_between[myActivityProbabilities["other_place"],myActivityProbabilities["work"]]{return "work";break;}
			match_between[myActivityProbabilities["work"],myActivityProbabilities["business"]]{return "business";break;}
			match_between[myActivityProbabilities["business"],myActivityProbabilities["school"]]{return "school";break;}
			match_between[myActivityProbabilities["school"],myActivityProbabilities["university"]]{return "university";break;}
			match_between[myActivityProbabilities["university"],myActivityProbabilities["shop"]]{return "shop";break;}
			match_between[myActivityProbabilities["shop"],myActivityProbabilities["authority"]]{return "authority";break;}
			match_between[myActivityProbabilities["authority"],myActivityProbabilities["doctor"]]{return "doctor";break;}
			match_between[myActivityProbabilities["doctor"],myActivityProbabilities["recreation"]]{return "recreation";break;}
			match_between[myActivityProbabilities["recreation"],myActivityProbabilities["bringing"]]{return "bringing";break;}
			default{lastActivity <- true; return "home"; break;} //if an activity type is null, then a person leaves the simulation or finishes its daily schedule by going home first.
		}
	}
	
	//Calculate a starting time	
	int calculateStartingTime{
		int earliestTime;
		int latestTime;
				
		switch activityType{
			//departure times for "school" and "university" activities are randomly selected between min and max times
			match "school"{
				earliestTime<- 420; latestTime<- 480;
				if cycle<=earliestTime{return rnd(earliestTime,latestTime);}
				else if cycle<=latestTime{return rnd(cycle,latestTime);}
				else{lastActivity<-true; return 9999;}
			}
			match "university"{
				earliestTime<- 480; latestTime<- 1080;
				if cycle<=earliestTime{return rnd(earliestTime,latestTime);}
				else if cycle<=latestTime{return rnd(cycle,latestTime);}
				else{lastActivity<-true; return 9999;}
			}
			default{
				map<int,float>startTimeProbability<-timeProbabilities[activityType][activityId];//select distribution of probabilities depending on activityType and activityId
				if length(startTimeProbability)=0 {lastActivity<-true;return 9999;}//finish daily travels and go home
				float timeThreshold <- timeThresholds[activityType][activityId];
				float rndNumberStartTime <- rnd(timeThreshold,max(startTimeProbability));
				loop k over:startTimeProbability.keys{
					if rndNumberStartTime>=timeThreshold and rndNumberStartTime<=startTimeProbability[k]{
						earliestTime<-60*(k-1);latestTime<-60*k;
						break;
					}else{
						timeThreshold<-startTimeProbability[k];
					}
				}
				return rnd(earliestTime,latestTime);
			}
		}
	}

	//Calculate a duration time depending on the type of the next activity
	int calculateDurationTime{
		int shortestDuration;//min duration
		int longestDuration;//max duration
		int leftTime;//time left before a facility closes
		
		//Select min/max durations
		switch activityType{
			match "home"{shortestDuration<-30;longestDuration<-60;leftTime<-1380;}
			//A duration for "pupil" depends on an age
			match "school"{
				switch age{
					match_between [6,7]{shortestDuration<-300;longestDuration<-300;leftTime<-960;}
					match_between [8,9]{shortestDuration<-420;longestDuration<-420;leftTime<-960;}
					match_between [10,13]{shortestDuration<-480;longestDuration<-480;leftTime<-960;}
					default{shortestDuration<-360;longestDuration<-480;leftTime<-960;}
				}
			}
			match "university"{shortestDuration<-120;longestDuration<-360;leftTime<-1200;}
			//A duration for "employed" depends on a gender and a probability distribution of working hours 
			match "work"{
				map<map<string,int>,float> workDurationProbability <- workDurationProbabilities[gender];
				float durationThreshold<-0.0;
				float rndNumberWorkDuration<- rnd(100.0);
				loop k over:workDurationProbability.keys{
					if rndNumberWorkDuration>=durationThreshold and rndNumberWorkDuration<=workDurationProbability[k]{
						shortestDuration<-k["min"];longestDuration<-k["max"];
						return rnd(shortestDuration,longestDuration);
					}else{
						durationThreshold<-workDurationProbability[k];
					}
				}
			}
			match "business"{shortestDuration<-15;longestDuration<-180;leftTime<-1080;}
			match "recreation"{shortestDuration<-60;longestDuration<-180;leftTime<-1380;}
			match "shop"{shortestDuration<-15;longestDuration<-120;leftTime<-1080;}
			match "other_place"{shortestDuration<-15;longestDuration<-180;leftTime<-1380;}
			match "authority"{shortestDuration<-30;longestDuration<-30;leftTime<-1080;}
			match "doctor"{shortestDuration<-60;longestDuration<-60;leftTime<-1080;}
			match "bringing"{shortestDuration<-15;longestDuration<-60;leftTime<-1080;}
		}
		
		//Calculate a duration
		leftTime <- leftTime-startingTime; //left time until a facility is closed
		if leftTime>=longestDuration{
			return rnd(shortestDuration,longestDuration);
		}else if leftTime>=shortestDuration{
			return rnd(shortestDuration,leftTime);
		}else{lastActivity<-true; return 9999;}
	}
	
	//Calculate a transport mode depending on a type of the next activity and location
	string calculateMode{
		map<string,float> modeProbability <- modeProbabilities[activityType][location overlaps cityOutline];
		float modeThreshold <- 0.0;
		float rndNumberMode <- rnd(100.00);
		loop k over:modeProbability.keys{
			if rndNumberMode>=modeThreshold and rndNumberMode<=modeProbability[k]{
				switch k{
					match "walk"{
						//Calculate minimum and maximum travel distances by mode based on distance probability distribution for "bike" and "walk"
						switch rnd(100.00){
							match_between [0.0,70.9908735332464]{minDistance <- 0.00; maxDistance <- 1000.00;break;}
							match_between [70.9908735332464,100.00]{minDistance <- 1000.00; maxDistance <- 5000.00;break;}
						}
						//Calculate a speed
						speed <- rnd(0.7,2.0);//0.7-2.0 m/s
					}
					match "bike"{
						switch rnd(100.00){
							match_between [0.0,72.9672650475185]{minDistance <- 0.00; maxDistance <- 2000.00;break;}
							match_between [72.9672650475185,100.00]{minDistance <- 2000.00; maxDistance <- 8000.00;break;}
						}
						speed <- rnd(1.6,5.5);//1.6-5.5 m/s
					}
					match "other_mode"{
						minDistance <- 0.00;
						maxDistance<-1000000.0;
						speed <- rnd(2.4,13.6);
					}
					default{
						minDistance <- 0.00;
						maxDistance<-1000000.0;
						speed <- rnd(4.9,14.9);
					}
				}
				return k;
			}else{
				modeThreshold<-modeProbability[k];
			}
		}
	}
	
	//Calculate a target location depending on activity type and allowed travel distances (min/max)
	point calculateTarget{
		facility rndFacility;
		switch activityType{
			match "home"{return homeLocation;}
			match "work"{
				//Select a work facility where the number of employees (facilityPopulation) is greater than 0
				rndFacility<-shuffle(facility) first_with(each.facilityType="work" and each.facilityPopulation>0 and between(distance_to(self,each.location),minDistance,maxDistance));
				//Select a work facility without distance restrictions, if there is no facility within allowed distances
				if rndFacility=nil{
					rndFacility <- shuffle(facility) first_with (each.facilityType="work" and each.facilityPopulation>0);
				}
				rndFacility.facilityPopulation <- rndFacility.facilityPopulation - 1;//decrease number of potential work places
				return any_location_in(rndFacility);
			}
			match "bringing"{
				rndFacility<-shuffle(facility) first_with((each.facilityType="kindergarten" or each.facilityType="doctor") and between(distance_to(self,each.location),minDistance,maxDistance));
				if rndFacility=nil{
					rndFacility <- shuffle(facility) first_with (each.facilityType="kindergarten" or each.facilityType="doctor");
				}
				return any_location_in(rndFacility);
			}
			default{
				rndFacility<-shuffle(facility) first_with(each.facilityType=activityType and between(distance_to(self,each.location),minDistance,maxDistance));
				if rndFacility=nil{
					rndFacility <- shuffle(facility) first_with (each.facilityType=activityType);
				}
				return any_location_in(rndFacility);
			}
		}
	}
	
	//Decide to move or teleport
    reflex start when:cycle = startingTime{
    	if mode = "bike"{ //if a mode is "bike"
    		path trip <-path_between(theGraph, sourceLocation,targetLocation);
    		if abs((first(trip.edges) as road).id)!=abs((last(trip.edges) as road).id) and first(trip.segments)!=last(trip.segments){ //if the start and end of a trip are not on the opposite roads
    			if trip.shape overlaps cityOutline{ //if a trip or the parts of a trip occur in the city
    				status <- "moving"; //move along the network
    			}
    		}
    	}
    	if status = "staying"{//if trip is not by bike or does not intersect the city or is very short and uses two links
    		location<-targetLocation;//don't move along the network but transfer to a target location
    		durationTime <- durationTime+int((distance_to (sourceLocation , targetLocation)/speed)/60.0);//update a duration time
		}
    }
    
	//Move
    reflex move when:status = "moving"{
		path pathFollowed <- goto (on:theGraph, target:targetLocation,move_weights: perimeterWeights, return_path:true);
    	if pathFollowed!=nil{
    		//Register a person at traversed completely roads
    		loop segment over:pathFollowed.segments{
				road traversedRoad<-road(pathFollowed agent_from_geometry segment);
				if point(theGraph target_of(traversedRoad)) overlaps segment{
					traversedRoad.cyclistsRoad<-traversedRoad.cyclistsRoad+1;
				}
			}
			//Register a person at traversed counting station
			ask countingStation overlapping(pathFollowed.shape){
				cyclistsStation <- cyclistsStation+1;
			}
    	}
    }
    
    //Stop at a target location
    reflex stop when:location=targetLocation{	
    	do saveTrip;
    	status <- "staying";
    	startingTime<-9999;
    	targetLocation <- nil;
    	sourceLocation<-nil;
		
    	if activityId=7 or lastActivity = true or endingTime>=1440{do die;}//remove a person from simulation
    }
	
	//Save trip information to "trips" file
    action saveTrip{
    	geometry tripGeom;//trip geometry
    	float tripLength;//travelled distance, in meters
    	float tripCityShare;//percentage of trip within city, in %
    	int tripTravelTime;//travel time, in min
    	int intersections;//number of intersections along a trip
    	if status = "moving"{//if a trip is made by "bike" and intersect the city
    		path trip <-path_between(theGraph, sourceLocation,targetLocation);
			tripGeom <- trip.shape;
			tripLength <- tripGeom.perimeter;
			tripCityShare<-(tripGeom inter cityOutline).perimeter*100/tripLength;
			tripTravelTime <- cycle-startingTime;
			intersections <- length(intersection overlapping(tripGeom));
			tripGeom<-CRS_transform(tripGeom);
    	}
    	if lastActivity=true{durationTime <- 1440-cycle;}//update a duration time
    	endingTime<-cycle+durationTime;
    	//save traip information as txt with ";" as a delimeter, since gama turn ; to , when saving as csv file
		save
			string(self) +";"+
			gender +";"+
			string(age) +";"+
			string(activityId) +";"+
			activityType +";"+			
			string(startingTime) +";"+
			string(endingTime) +";"+
			string(durationTime) +";"+
			string(tripTravelTime) +";"+
			mode +";"+
			string(speed) +";"+
			string(tripLength) +";"+
			string(tripCityShare) +";"+
			string(intersections) +";"+
			string(tripGeom) +";"
		 to: tripsFileName type:"text" rewrite:false;
	}
}

//Facility species represent the locations by activity type
species facility schedules:[]{
	string facilityType;
	int facilityPopulation; //number of employees at "work" facilities
	aspect base{
		draw shape color:#cadetblue;
	}
}

//Road species represent directional and connected links that form street network.
species road frequency:networkTimeInterval{
	int id; //unique identifier
	float safetyIndex; //level of safety
	float weight; //routing weight: perimeter value - for the shortest path algorithm, safety index value - for the safest path algorithm
	int restriction; //"0" - not restricted, "1" - restricted for motorized vehicles, allowed to push bike, "2" - restricted for every type of mode
	float linkLength; //perimeter
	road oppositeRoad; //road with opposite direction

	int cyclistsRoad <- 0; //number of traversed cyclists every specified interval of time
	map<int,int> cyclistsByInterval; //list of number of traversed cyclists every specified interval of time
	int cyclistsTotal <- 0; //total amount of traversed cyclists

	aspect base{
		draw shape 
		color:rgb(max([105, min([255, 105+int(cyclistsTotal*0.15)])]),max([105, min([255, 105+int(cyclistsTotal*0.15)])]),max([105, min([255, 105+int(cyclistsTotal*0.15)])]))
		width:1+cyclistsTotal*0.005;
	}
	
	//Update number of traversed cyclists every specified interval of time.
    reflex updateCyclists when:every(networkTimeInterval#cycle){
    	if oppositeRoad!=nil{// traverses of cyclists over an opposite road are registered by an original road
    		cyclistsRoad<-cyclistsRoad+oppositeRoad.cyclistsRoad;
    	}
    	add cyclistsRoad at:cycle to:cyclistsByInterval;
    	cyclistsTotal<-cyclistsTotal+cyclistsRoad;
    	cyclistsRoad<- 0;
    }
}

//Road intersections
species intersection schedules:[];

//Counting stations that register traversing cyclists every specified interval of time
species countingStation frequency:countingStationTimeInterval{
	string stationName;
	int cyclistsStation<-0; //number of traversed cyclists every specified interval of time
	int cyclistsStationChart <-0; //number of traversed cyclists every specified interval of time for the chart display
	map<int,int> observedCounts; //number of traversed cyclists from the observed data

	aspect base{
		draw circle(0.1) color:#mediumorchid;
	}
	
	//Register cyclists that passed counting stations every "countingStationTimeInterval" of cycles (min)
	reflex saveCoutningData when: every(countingStationTimeInterval#cycle){
		save [cycle,stationName,cyclistsStation] to:countsFileName type:"csv" rewrite:false;
		cyclistsStationChart<-cyclistsStation;
		cyclistsStation <- 0;
	}
}

//////////////////////////////////////////////EXPERIMENT///////////////////////////////////////////////////////////////////////////////
experiment bicycle_model type:gui{
	parameter "interval to save cyclists on network, in min" category:"Output parameters" var:networkTimeInterval<-60;
	parameter "interval to save cyclists at counting stations, in min" category:"Output parameters" var:countingStationTimeInterval<-60;
	parameter "interval to save active cyclists, in min" category:"Output parameters" var:activeCylistsTimeInterval<-60;
	parameter "routing algorithm" category:"Network" var: routingAlgorithm <- "safest path" among:["safest path","shortest path"];
	parameter "bicycle infrastructure weight" category:"Network" var: bicycleInfrastructureWeight <-0.2;
	parameter "traffic volume of motorized vehicles weight" category:"Network" var: mitVolumeWeight<-0.0;
	parameter "designated route weight" category:"Network" var: designatedRouteWeight<-0.1;
	parameter "road category weight" category:"Network" var: roadCategoryWeight<-0.3;
	parameter "max speed weight" category:"Network" var: maxSpeedWeight<-0.1;
	parameter "adjacent edge weight" category:"Network" var: adjacentEdgeWeight<-0.0;
	parameter "parking weight" category:"Network" var: parkingWeight<-0.1;
	parameter "pavement weight" category:"Network" var: pavementWeight<-0.1;
	parameter "lane width weight" category:"Network" var: widthLaneWeight<-0.0;
	parameter "gradient weight" category:"Network" var: gradientWeight<-0.1;
	parameter "rails weight" category:"Network" var: railsWeight<-0.0;
	parameter "lanes number weigth" category:"Network" var: numberLaneWeight<-0.0;
	parameter "landuse weight" category:"Network" var: landuseWeight<-0.0;
	parameter "designated route adjusted weight" category:"Network" var: designatedRouteAdjusted<-2.0;
	parameter "rails adjusted weight" category:"Network" var: railsAdjusted<-0.6;
	parameter "pavement adjusted weight" category:"Network" var: pavementAdjusted<-0.4;
	parameter "gradient adjusted weight" category:"Network" var: gradientAdjusted<-0.4;
	parameter "bridge value" category:"Network" var: bridgeValue<-3.0;
	parameter "push value" category:"Network" var: pushValue<-3.0;
	output{
		display city_map type:opengl background:rgb(10,40,55){
			species road aspect:base;
			species countingStation aspect:base;
			species person aspect: base;
		}
		
		display activeAgents type:java2D refresh:every(10#cycle){
			chart "Total number of active cyclists" type: series size: {1, 0.5} position: {0,0}{
				data "Active cyclists" value: person count (each.status="moving") style:line color:#black;
			}
			chart "Active cyclists by trip purpose" type: series size: {1, 0.5} position: {0, 0.5}{
				data "School" value: person count (each.status="moving" and each.activityType="school") style:line color:#mediumseagreen;
				data "University" value: person count (each.status="moving" and each.activityType="university") style:line color:#plum;
				data "Work" value: person count (each.status="moving" and each.activityType="work") style:line color:#royalblue;
				data "Recreation" value: person count (each.status="moving" and each.activityType="recreation") style:line color:#khaki;
				data "Shop" value: person count (each.status="moving" and each.activityType="shop") style:line color:#chocolate;
				data "Other activity" value: person count (each.status="moving" and each.activityType="other_place") style:line color:#darkcyan;
				data "Home" value: person count (each.status="moving" and each.activityType="home") style:line color:#cadetblue;
				data "Business" value: person count (each.status="moving" and each.activityType="business") style:line color:#maroon;
				data "Authority" value: person count (each.status="moving" and each.activityType="authority") style:line color:#darkgrey;
				data "Doctor" value: person count (each.status="moving" and each.activityType="doctor") style:line color:#coral;
				data "Bringing" value: person count (each.status="moving" and each.activityType="bringing") style:line color:#seagreen;
			}
		}
		display activeAgentsAtStations type:java2D refresh:every(60#cycle){
			chart "Active cyclists at "+countingStation(0).stationName+" per hour" type: series size: {0.3, 0.3} position: {0, 0}{
				data "simulated counts" value: countingStation(0).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(0).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(1).stationName+" per hour" type: series size: {0.3, 0.3} position: {0.3,0}{
				data "simulated counts" value: countingStation(1).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(1).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(2).stationName+" per hour" type: series size: {0.3, 0.3} position: {0.6,0}{
				data "simulated counts" value: countingStation(2).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(2).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(3).stationName+" per hour" type: series size: {0.3, 0.3} position: {0,0.3}{
				data "simulated counts" value: countingStation(3).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(3).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(4).stationName+" per hour" type: series size: {0.3, 0.3} position: {0.3,0.3}{
				data "simulated counts" value: countingStation(4).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(4).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(5).stationName+" per hour" type: series size: {0.3, 0.3} position: {0.6,0.3}{
				data "simulated counts" value: countingStation(5).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(5).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(6).stationName+" per hour" type: series size: {0.3, 0.3} position: {0,0.6}{
				data "simulated counts" value: countingStation(6).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(6).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(7).stationName+" per hour" type: series size: {0.3, 0.3} position: {0.3,0.6}{
				data "simulated counts" value: countingStation(7).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(7).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
			chart "Active cyclists at "+countingStation(8).stationName+" per hour" type: series size: {0.3, 0.3} position: {0.6,0.6}{
				data "simulated counts" value: countingStation(8).cyclistsStationChart style:line color:#goldenrod;
				data "observed counts" value: countingStation(8).observedCounts[int(cycle/60)] style:line color:#gamablue;
			}
		}
	}
}