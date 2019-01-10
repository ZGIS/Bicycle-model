/* 
* Name: Bicycle model
* Authors: Kaziyeva, D., Wallentin, G, Loidl, M.
* Acknowledgements: The model is built on GAMA toy model "Simple traffic model" by Patrick Taillandier and extends "Salzburg Bicycle Model" by Gudrun Wallentin and Martin Loidl (Wallentin, Gudrun (2016, October 29). “Salzburg Bicycle model” (Version 1.0.0). CoMSES Computational Model Library. Retrieved from: https://www.comses.net/codebases/5259/releases/1.0.0/)
* Description: The purpose of the model is to generate disaggregated traffic flow distribution of cyclists at the regional scale level. 
* The model is fuelled by statistical and topographical data as well as by generalized assumptions derived from survey data on mobility behaviour. 
* It results in emergent flow patterns at a high spatial and temporal level of detail.
* Licence: CC BY-NC-SA 3.0 (http://creativecommons.org/licenses/by-nc-sa/3.0/)
* Tags: traffic, bicycle
*/

model bicycle_model

global{
	//Input data	
	file fileHomePlaces <- file("../includes/model_input/shapefiles/homes.shp");//residential data (250m resolution) with population values by age groups and gender
	file fileWorkPlaces <- file("../includes/model_input/shapefiles/work_places.shp");//employees data (100m resolution) that represent number of employees that work at each cell.
	file fileUniversities <- file("../includes/model_input/shapefiles/universities.shp");//locations of universities and educational institutions
	file fileSchools <- file("../includes/model_input/shapefiles/schools.shp");//locations of schools
	file fileShops <- file("../includes/model_input/shapefiles/shops.shp");//locations of shops
	file fileRecreationPlaces <- file("../includes/model_input/shapefiles/recreation.shp");//locations of recreation facilities
	file fileKindergardens <- file("../includes/model_input/shapefiles/kindergardens.shp");//locations of kindergardens that are assumed as facilities where "bringing" activity is carried out.
	file fileDoctors <- file("../includes/model_input/shapefiles/hospitals.shp");//locations of hospitals and doctors that are assumed as facilities where "bringing" activity is carried out.
	file fileAuthorities <- file("../includes/model_input/shapefiles/authorities.shp");//locations of authorities
	file fileCountingStations <- file("../includes/model_input/shapefiles/counting_stations.shp");//locations of bicycle counting stations
	file fileRoads <- file("../includes/model_input/shapefiles/network.shp");//network
	file fileCityOutline<- file("../includes/model_input/shapefiles/outline_city.shp");//outline of a city to define belonging of roads and facilities to either to a city or a region.
	file fileCounts <- file("../includes/model_input/csv_files/real_counts.csv");//real counting data from counting stations for comparison in a chart
	file fileActivityProbabilities <- file("../includes/model_input/csv_files/activity_probabilities.csv");//activity probabilities by activity types and by position. Maximum number of activities is 8 activities/day.
	file fileTimeProbabilities <- file("../includes/model_input/csv_files/time_probabilities.csv");//probability distribution of departure time by activity type and by hour of day from 0-100%.
	file fileModeProbabilities <- file("../includes/model_input/csv_files/mode_probabilities.csv");//probability distribution of transportation mode by activity types and by region extend from 0-100%. Region extends are city and region.
	
	//File path names of output data 
	string heatmapFileName <- "../includes/model_output/heatmap.shp";//heatmap of a road network with calculated bicycle traffic volume per network link and by hour
	string countsFileName <- "../includes/model_output/counts.csv";//csv file to save number of passed cyclists at counting stations every specified period of cycles
	string activitiesFileName <- "../includes/model_output/activities.csv";//csv file to save all(finished and unfinished) activities that were assigned to people
	string tripsFileName<- "../includes/model_output/trips.txt";//csv file to save trips made by only "bike" mode
	string activeCyclistsFileName <- "../includes/model_output/active_cyclists.csv";//csv file to save number of moving cyclists by trip purpose every specified time period of cycles
	string originsFileName <- "../includes/model_output/origins.csv";//csv file to save locations of all trip origins(starting points) as coordinates
	string destinationsFileName <- "../includes/model_output/destinations.csv";//csv file to save locations of all trip destinations as coordinates
	
	//Model parameters
	geometry shape<- envelope(fileRoads);//extend of a simulated world
	float step <- 1 #mn;//simulation step defined by minutes in a real world
	float simulationStartTime;//machine time at the beginning of simulation run (excluding initialization time)
	int countingStationTimeInterval<-60;//time interval in cycles (= minutes) when passed cyclists are saved as an output
	int activeCylistsTimeInterval<-15;//time interval in cycles (= minutes) when all moving("active") cyclists are saved
	
	//Facility variables
	string showFacility;//user-defined model parameter to visualize facilities by type on a display. The default is "none".
	list<facility> workFacilityList;//list of work facilities
	
	//Network variables
	graph theGraph;//bidirectional network graph composed of road species
	map<road,float> perimeterWeights;//map variable with road and its weight set to perimeter
	map<road,float> safetyIndexWeights;//map variable with road and its weight set to safety index
	string routingAlgorithm;//user-defined model parameter to select routing algorithm: "shortest path", "safest path". Deafault is "safest path".
	//attribute weights needed for assessment of network and calculation of safety index
	float bicycleInfrastructureWeight<-0.2;//weight for bicycle infrastructure
	float mitVolumeWeight<-0.0;//weight for motorized traffic volume attribute
	float designatedRouteWeight<-0.1;//weight for designated route attribute
	float roadCategoryWeight<-0.3;//weight for road category attribute
	float maxSpeedWeight<-0.1;//weight for maximal speed attribute
	float adjacentEdgeWeight<-0.0;//weight for adjacent edge attribute
	float parkingWeight<-0.1;//weight for parking attribute
	float pavementWeight<-0.1;//weight for pavement attribute
	float widthLaneWeight<-0.0;//weight for width lane attribute
	float gradientWeight<-0.1;//weight for gradient attribute
	float railsWeight<-0.0;//weight for rails attribute
	float numberLaneWeight<-0.0;//weight for lane number attribute
	float landuseWeight<-0.0;//weight for landuse attribute
	float designatedRouteAdjusted<-2.0;//adjusted weight for constraction status attribute
	float railsAdjusted<-0.6;//adjusted weight for rails attribute
	float pavementAdjusted<-0.4;//adjusted weight for pavement
	float gradientAdjusted<-0.4;//adjusted weight for gradient
	float bridgeValue<-3.0;//bridge value
	float pushValue<-3.0;//push value
	
	//Activity probabilities by activity type and position from position 0(initial position) to 7. In a list of probabilities activity types are in the following order: "home","other_place","work","business","school","university","shop","authority","doctor","recreation","bringing"
	list<float>activityProbabilities0;//activity probabilities when activity position =0
	list<float>activityProbabilities1;//activity probabilities when activity position =1...
	list<float>activityProbabilities2;
	list<float>activityProbabilities3;
	list<float>activityProbabilities4;
	list<float>activityProbabilities5;
	list<float>activityProbabilities6;
	list<float>activityProbabilities7;
	
	//Distribution of departure time probabilities by activity type and actvity position. Each container is defined by activity type. Container is composed of lists. Lists are defined by activity position (0-7). Each list is composed of distribution of departure time probabilities (0-100%) by hour (24 hours)
	container<list<float>> startTimeProbabilitiesHome;
	container<list<float>> startTimeProbabilitiesOtherPlace;
	container<list<float>> startTimeProbabilitiesWork;
    container<list<float>> startTimeProbabilitiesBusiness;
    container<list<float>> startTimeProbabilitiesShop;
    container<list<float>> startTimeProbabilitiesAuthority;
    container<list<float>> startTimeProbabilitiesDoctor;
    container<list<float>> startTimeProbabilitiesRecreation;
    container<list<float>> startTimeProbabilitiesBringing;
    
    //Mode probabilities distribution by activity type and spatial extend. Modes are presented in the folllowing order: "walk","bike","car","car_passenger","public_transport","other_mode". Spatial extend values are city and region.
    container<list<float>> modeProbabilitiesHome;
	container<list<float>> modeProbabilitiesOtherPlace;
	container<list<float>> modeProbabilitiesWork;
    container<list<float>> modeProbabilitiesBusiness;
    container<list<float>> modeProbabilitiesSchool;
    container<list<float>> modeProbabilitiesUniversity;
    container<list<float>> modeProbabilitiesShop;
    container<list<float>> modeProbabilitiesAuthority;
    container<list<float>> modeProbabilitiesDoctor;
    container<list<float>> modeProbabilitiesRecreation;
    container<list<float>> modeProbabilitiesBringing;
	list<string> oldModes;//list of modes that are not assigned due to a failure to meet a threshold of maximum distance between origin and destination.
	float sharePupil;//share of pupil among pupils and students together
	float shareStudent;//share of students among pupils and students together
	
	//Initialzation
	init{
		float initializationStartTime <- machine_time;//machine time when an initialization starts
		do uploadProbabilities;//load probabilities from csv files
		do createCityOutline;//load city outline
		do createPopulation;//create home species
		do updateModalSplit;
		do createFacilities;//create facility species
		do createRoads;//create road species and a network graph
		do createCountingStations;//create counting stations
		save "self;activityId;finished;lastActivity;mode;activityType;startingTime;"+
			 "endingTime;durationTime;travelTime;speed;activityDistance;traversedIntersections;"+
			 "cityShare;track_geom;sourceLocation_x;sourceLocation_y;targetLocation_x;targetLocation_y;"+
			 "sourceWithinCity;targetWithinCity;male;female;age"to:tripsFileName type:"text" rewrite:false;
		write "duration of initialization: " + (machine_time - initializationStartTime)/1000; //output of total time spent to initialize a model
	}
	
	//Load probabilities distributions of activity types, departure times and modes
	action uploadProbabilities{
		//Load activity types probabilities
		matrix activityMatrix <- matrix(fileActivityProbabilities);
		loop actTypeColumn from: 1 to: activityMatrix.columns-1{//from column 1 in the matrix probabilty values by activity type are represented. Rows from 0 to 7 represent activity positions
			add float(activityMatrix[actTypeColumn,0]) to:activityProbabilities0;
			add float(activityMatrix[actTypeColumn,1]) to:activityProbabilities1;
			add float(activityMatrix[actTypeColumn,2]) to:activityProbabilities2;
			add float(activityMatrix[actTypeColumn,3]) to:activityProbabilities3;
			add float(activityMatrix[actTypeColumn,4]) to:activityProbabilities4;
			add float(activityMatrix[actTypeColumn,5]) to:activityProbabilities5;
			add float(activityMatrix[actTypeColumn,6]) to:activityProbabilities6;
			add float(activityMatrix[actTypeColumn,7]) to:activityProbabilities7;
		}
		remove fileActivityProbabilities from:self;
		
		//Load departure times probabilities into containers. Containers differ by activity type. A container holds lists by activity position. A list holds probabilities by hour.
		matrix timeMatrix <- matrix(fileTimeProbabilities);
		int rowCounter<-0;//variable that is used for looping through activity types. It will be increased every (actType) loop by 7, since for every activity type there are 7 activity positions when departure time has to be calculated (activity at position "0 " is excluded because it is an initial position of a person. 
		loop actType from:0 to:8{//there are 9 types of activities to loop through:"home","other_place","work","business","shop","authority","doctor","recreation","bringing"
			container<list<float>> timeProbabilitiesContainer;//container variable that holds startTimeProbabilities containers by activity type to be filled.
			switch actType{
				match 0{timeProbabilitiesContainer<- startTimeProbabilitiesHome;}
				match 1{timeProbabilitiesContainer<- startTimeProbabilitiesOtherPlace;}
				match 2{timeProbabilitiesContainer<- startTimeProbabilitiesWork;}
				match 3{timeProbabilitiesContainer<- startTimeProbabilitiesBusiness;}
				match 4{timeProbabilitiesContainer<- startTimeProbabilitiesShop;}
				match 5{timeProbabilitiesContainer<- startTimeProbabilitiesAuthority;}
				match 6{timeProbabilitiesContainer<- startTimeProbabilitiesDoctor;}
				match 7{timeProbabilitiesContainer<- startTimeProbabilitiesRecreation;}
				match 8{timeProbabilitiesContainer<- startTimeProbabilitiesBringing;}
			}
			loop position from:1+rowCounter to: 7+rowCounter{
				list<float>timeProbabilities;//list that holds departure time probabilities by position
				loop timeColumn from: 2 to: timeMatrix.columns-1{//from column 2 in the timeMatrix values represent probabilities by hour
					add float(timeMatrix[timeColumn,position]) to:timeProbabilities;
				}
				add timeProbabilities to: timeProbabilitiesContainer;//add a list to a container
			}
			rowCounter <- rowCounter+7;//update a rowCounter
		}
		remove fileTimeProbabilities from:self;
		
		//Load mode types probabilities. Containers differ by activity type. A container holds two lists that are different by spatial extend: city and region. A list contains modal split probabilities by mode type.
		matrix modeMatrix <- matrix(fileModeProbabilities);
		rowCounter<-0;//here this variable is used to loop through activity types, with the difference in its increase by 2, since there are two types of spatial extend
		loop actType from:0 to:10{//there are 11 activity types to loop through
			container<list<float>> modeProbabilitiesContainer;
			switch actType{
				match 0{modeProbabilitiesContainer<- modeProbabilitiesHome;}
				match 1{modeProbabilitiesContainer<- modeProbabilitiesOtherPlace;}
				match 2{modeProbabilitiesContainer<- modeProbabilitiesWork;}
				match 3{modeProbabilitiesContainer<- modeProbabilitiesBusiness;}
				match 4{modeProbabilitiesContainer<- modeProbabilitiesSchool;}
				match 5{modeProbabilitiesContainer<- modeProbabilitiesUniversity;}
				match 6{modeProbabilitiesContainer<- modeProbabilitiesShop;}
				match 7{modeProbabilitiesContainer<- modeProbabilitiesAuthority;}
				match 8{modeProbabilitiesContainer<- modeProbabilitiesDoctor;}
				match 9{modeProbabilitiesContainer<- modeProbabilitiesRecreation;}
				match 10{modeProbabilitiesContainer<- modeProbabilitiesBringing;}
			}
			loop position from:0+rowCounter to: 1+rowCounter{
				list<float>modeProbabilities;//list that holds modal split probabilities
				loop modeColumn from: 2 to: modeMatrix.columns-1{//from column 2 in matrix values represent probabilities by mode type
					add float(modeMatrix[modeColumn,position]) to:modeProbabilities;
				}
				add modeProbabilities to: modeProbabilitiesContainer;//add a list to a container
			}
			rowCounter <- rowCounter+2;//update a rowCounter
		}
		remove fileModeProbabilities from:self;
	}
	
	//Create species "cityOutline"
	action createCityOutline{
		create cityOutline from:fileCityOutline;
	}
	
	//Create species "home", see attribute descriptions in species definition section below
	//Create species "people" based on demographic attributes of home species
	action createPopulation {
		create home from: fileHomePlaces with: [
			id::string(read("id")),
			HOME_POPULATION::int(read("residents")),MALE_BELOW_5::int(read("m_below_5")),MALE_5_9::int(read("m_5_9")),
			MALE_10_14::int(read("m_10_14")),MALE_15_19::int(read("m_15_19")),MALE_20_24::int(read("m_20_24")),MALE_25_29::int(read("m_25_29")),MALE_30_34::int(read("m_30_34")),
			MALE_35_39::int(read("m_35_39")),MALE_40_44::int(read("m_40_44")),MALE_45_49::int(read("m_45_49")),MALE_50_54::int(read("m_50_54")),MALE_55_59::int(read("m_55_59")),
			MALE_60_64::int(read("m_60_64")),MALE_65_69::int(read("m_65_69")),MALE_70_74::int(read("m_70_74")),MALE_75_79::int(read("m_75_79")),MALE_80_84::int(read("m_80_84")),
			MALE_85_89::int(read("m_85_89")),MALE_90_94::int(read("m_90_94")),MALE_95_99::int(read("m_95_99")),MALE_over_100::int(read("m_over_100")),
			FEMALE_BELOW_5::int(read("f_below_5")),FEMALE_5_9::int(read("f_5_9")),FEMALE_10_14::int(read("f_10_14")),FEMALE_15_19::int(read("f_15_19")),FEMALE_20_24::int(read("f_20_24")),FEMALE_25_29::int(read("f_25_29")),
			FEMALE_30_34::int(read("f_30_34")),FEMALE_35_39::int(read("f_35_39")),FEMALE_40_44::int(read("f_40_44")),FEMALE_45_49::int(read("f_45_49")),FEMALE_50_54::int(read("f_50_54")),
			FEMALE_55_59::int(read("f_55_59")),FEMALE_60_64::int(read("f_60_64")),FEMALE_65_69::int(read("f_65_69")),FEMALE_70_74::int(read("f_70_74")),FEMALE_75_79::int(read("f_75_79")),
			FEMALE_80_84::int(read("f_80_84")),FEMALE_85_89::int(read("f_85_89")),FEMALE_90_94::int(read("f_90_94")),FEMALE_95_99::int(read("f_95_99")),FEMALE_over_100::int(read("f_over_100")),
			MALE_EMPLOYED::int(read("m_employed")),MALE_UNEMPLOYED::int(read("m_unemploy")),MALE_BELOW_15::int(read("m_below_15")),MALE_PENSIONERS::int(read("m_pension")),
			MALE_PUPILS_STUDENTS_OVER_15::int(read("m_students")),MALE_INACTIVE::int(read("m_inactive")),MALE_UNKNOWN_EMPLOYMENT_STATUS::int(read("m_emp_unk")),
			FEMALE_EMPLOYED::int(read("f_employed")),FEMALE_UNEMPLOYED::int(read("f_unemploy")),FEMALE_BELOW_15::int(read("f_below_15")),FEMALE_PENSIONERS::int(read("f_pension")),
			FEMALE_PUPILS_STUDENTS_OVER_15::int(read("f_students")),FEMALE_INACTIVE::int(read("f_inactive")),FEMALE_UNKNOWN_EMPLOYMENT_STATUS::int(read("f_emp_unk")),
			PUPILS_6_14::int(read("pupil6_14")),PUPILS_15_19::int(read("pupil15_19")),STUDENTS::int(read("students"))
		]{
			if HOME_POPULATION=0{do die;}
			maleByAge<-[MALE_BELOW_5,MALE_5_9,MALE_10_14,MALE_15_19,MALE_20_24,MALE_25_29,MALE_30_34,MALE_35_39,MALE_40_44,MALE_45_49,MALE_50_54,MALE_55_59,MALE_60_64,MALE_65_69,MALE_70_74,MALE_75_79,MALE_80_84,MALE_85_89,MALE_90_94,MALE_95_99,MALE_over_100];
			femaleByAge<-[FEMALE_BELOW_5,FEMALE_5_9,FEMALE_10_14,FEMALE_15_19,FEMALE_20_24,FEMALE_25_29,FEMALE_30_34,FEMALE_35_39,FEMALE_40_44,FEMALE_45_49,FEMALE_50_54,FEMALE_55_59,FEMALE_60_64,FEMALE_65_69,FEMALE_70_74,FEMALE_75_79,FEMALE_80_84,FEMALE_85_89,FEMALE_90_94,FEMALE_95_99,FEMALE_over_100];
		}
		float t2 <- machine_time;
		
		ask home{
			do createPeople;
			do die;//remove home species
		}
		write "Employment status is assigned: "+ (machine_time - t2)/1000;		
		write "People are created: "+people count(true);
	}
	
	//Due to one activity probability for both school and university in input data, "school" and "university" probabilities are updated in relation to number of created pupils and students.
	action updateModalSplit{
    	int numberPupilsStudents <-  length(people where(each.employmentStatus = "pupil" or each.employmentStatus = "employed_pupil" or each.employmentStatus = "student" or each.employmentStatus = "employed_student"));//total number of all pupils and students
		sharePupil <- length(people where(each.employmentStatus = "pupil" or each.employmentStatus = "employed_pupil"))*100/numberPupilsStudents;//share of pupils in %
		shareStudent <- 100.00-sharePupil;//share of students in %
		//Values indexed under 4 in the probabilities list stands for school, 5 stands for university. Both initial values are the same and represent total probability for both activities.
		activityProbabilities0[4] <-activityProbabilities0[4]* sharePupil/100;
		activityProbabilities0[5] <-activityProbabilities0[5]* shareStudent/100;
		activityProbabilities1[4] <-activityProbabilities1[4]* sharePupil/100;
		activityProbabilities1[5] <-activityProbabilities1[5]* shareStudent/100;
		activityProbabilities2[4] <-activityProbabilities2[4]* sharePupil/100;
		activityProbabilities2[5] <-activityProbabilities2[5]* shareStudent/100;
		activityProbabilities3[4] <-activityProbabilities3[4]* sharePupil/100;
		activityProbabilities3[5] <-activityProbabilities3[5]* shareStudent/100;
		activityProbabilities4[4] <-activityProbabilities4[4]* sharePupil/100;
		activityProbabilities4[5] <-activityProbabilities4[5]* shareStudent/100;
		activityProbabilities5[4] <-activityProbabilities5[4]* sharePupil/100;
		activityProbabilities5[5] <-activityProbabilities5[5]* shareStudent/100;
		activityProbabilities6[4] <-activityProbabilities6[4]* sharePupil/100;
		activityProbabilities6[5] <-activityProbabilities6[5]* shareStudent/100;
		activityProbabilities7[4] <-activityProbabilities7[4]* sharePupil/100;
		activityProbabilities7[5] <-activityProbabilities7[5]* shareStudent/100;
    }
	
	//Create species "facility"
	action createFacilities{
		create facility from: fileHomePlaces{facilityType <- "home";facilityColor<-#firebrick;}
		create facility from: fileWorkPlaces with: [facilityPopulation::int(read("employees"))]{//work facilities hold information about number of employees
			facilityType <- "work";
			facilityColor<-#deepskyblue;
			if facilityPopulation>0{add self to:workFacilityList;}
		}
		create facility from: fileWorkPlaces{facilityType <- "business";facilityColor<-#indianred;}//business facilties are defined by work places
		create facility from: fileUniversities{facilityType <- "university";facilityColor<-#green;}
		create facility from: fileSchools{facilityType <- "school";facilityColor<-#darkslateblue;}
		create facility from: fileShops{facilityType <- "shop";facilityColor<-#slateblue;}
		create facility from: fileRecreationPlaces{facilityType <- "recreation";facilityColor<-#cadetblue;}
		create facility from: fileDoctors{facilityType <- "bringing";facilityColor<-#tan;}//bringing facilties are defined by places of hospitals and doctor clinics as well as kindergardens. Chilldren and old people are brought to such facilities.
		create facility from: fileKindergardens{facilityType <- "bringing";facilityColor<-#tan;}
		create facility from: fileHomePlaces{facilityType <- "other_place";facilityColor<-#darkviolet;}//other place facilities are defined as trips to friends and families(their homes)
		create facility from: fileDoctors{facilityType <- "doctor";facilityColor<-#steelblue;}
		create facility from: fileAuthorities{facilityType <- "authority";facilityColor<-#palegreen;}
		ask facility{//if a user selects facility type to show, all facilities with this type will be displayed on a map
			if showFacility!=facilityType{facilityColor<-#transparent;}
		}
		remove fileHomePlaces from:self;
		remove fileWorkPlaces from:self;
		remove fileUniversities from:self;
		remove fileSchools from:self;
		remove fileShops from:self;
		remove fileRecreationPlaces from:self;
		remove fileKindergardens from:self;
		remove fileDoctors from:self;
		remove fileAuthorities from:self;
	}
    
	//Create species "road".  Attributes depend on road directions. Initial network file has attributes for both directions. FT is from-to(nodes) direction, TF is to-from(nodes) direction. 
	action createRoads{
		float t2 <- machine_time;
		create road from: fileRoads with:[
			linkId::float(read("linkid")),
			brunnel::int(read("brunnel")),
			baseType::string(read("basetype")),
			bicycleInfrastructureFT::string(read("bic_inf_ft")),
			bicycleInfrastructureTF::string(read("bic_inf_tf")),
			mitVolumeFT::int(read("mit_vol_ft")),
			mitVolumeTF::int(read("mit_vol_tf")),
			designatedRouteFT::string(read("d_route_ft")),
			designatedRouteTF::string(read("d_route_tf")),
			roadCategory::string(read("road_categ")),
			maxSpeedFT::int(read("max_sp_ft")),
			maxSpeedTF::int(read("max_sp_tf")),
			adjacentEdgeFT::int(read("ad_edge_ft")),
			adjacentEdgeTF::int(read("ad_edge_tf")),
			parkingFT::string(read("parking_ft")),
			parkingTF::string(read("parking_tf")),
			pavement::string(read("pavement")),
			widthLane::int(read("width_lane")),
			gradientFT::int(read("grad_ft")),
			gradientTF::int(read("grad_tf")),
			rails::string(read("rails")),
			numberLaneFT::int(read("n_lanes_ft")),
			numberLaneTF::int(read("n_lanes_tf")),
			landuse::string(read("land_use")),
			onewayFT::int(read("oneway_ft")),
			onewayTF::int(read("oneway_tf")),
			restrictionFT::int(read("restric_tf")),
			restrictionTF::int(read("restric_ft")),
			intersectionId1::int(read("intersect1")),
			intersectionId2::int(read("intersect2")),
			intersections::int(read("n_intersec")),
			city::int(read("city")),
			shapeLength::float(read("length"))]{
			if onewayFT = 1 and onewayTF = 0{//if a link has one direction "FT"
				bicycleInfrastructure <- bicycleInfrastructureFT;
				mitVolume<-mitVolumeFT;
				designatedRoute <- designatedRouteFT;
				maxSpeed <- maxSpeedFT;
				adjacentEdge <- adjacentEdgeFT;
				parking <- parkingFT;
				gradient <- gradientFT;
				numberLane <- numberLaneFT;
				oneway <- 1;
				restriction <- restrictionFT;
				do calculateSafetyIndex;
				weight <- (1+safetyIndex)*5-4;//calculate weight based on safety index for safest routing algorithm
			}
			if onewayFT = 0 and onewayTF = 1{//if a link has one direction "TF"
				shape <- polyline(reverse(shape.points));//reverse link geometry, so that it will have an opposite direction
				bicycleInfrastructure <- bicycleInfrastructureTF;
				mitVolume<-mitVolumeTF;
				designatedRoute <- designatedRouteTF;
				maxSpeed <- maxSpeedTF;
				adjacentEdge <- adjacentEdgeTF;
				parking <- parkingTF;
				gradient <- gradientTF;
				numberLane <- numberLaneTF;
				oneway <- 1;
				restriction <- restrictionTF;
				do calculateSafetyIndex;
				weight <- (1+safetyIndex)*5-4;//calculate weight based on safety index for safest routing algorithm
			}
			if onewayFT = 0 and onewayTF = 0{//if a link has two derections, create two roads with geometries that have opposite directions
				bicycleInfrastructure <- bicycleInfrastructureFT;
				mitVolume<-mitVolumeFT;
				designatedRoute <- designatedRouteFT;
				maxSpeed <- maxSpeedFT;
				adjacentEdge <- adjacentEdgeFT;
				parking <- parkingFT;
				gradient <- gradientFT;
				numberLane <- numberLaneFT;
				oneway <- 0;
				restriction <- restrictionFT;
				do calculateSafetyIndex;
				weight <- (1+safetyIndex)*5-4;
				create road{	
					shape <- polyline(reverse(myself.shape.points));
					reversedRoad <- myself;
					linkId <- myself.linkId;
					brunnel<- myself.brunnel;
					baseType<-myself.baseType;
					bicycleInfrastructure <- myself.bicycleInfrastructureTF;
					mitVolume<-myself.mitVolumeTF;
					designatedRoute <- myself.designatedRouteTF;
					roadCategory<- myself.roadCategory;
					maxSpeed <- myself.maxSpeedTF;
					adjacentEdge <- myself.adjacentEdgeTF;
					parking <- myself.parkingTF;
					pavement<- myself.pavement;
					widthLane<- myself.widthLane;
					gradient <- myself.gradientTF;
					rails<- myself.rails;
					numberLane <- myself.numberLaneTF;
					landuse <- myself.landuse;
					oneway <- 0;
					restriction <- myself.restrictionTF;
					intersectionId1<- myself.intersectionId1;
					intersectionId2<- myself.intersectionId2;
					intersections<- myself.intersections;
					city<-myself.city;
					shapeLength <-myself.shapeLength;
					do calculateSafetyIndex;
					weight <- (1+safetyIndex)*5-4;
				}
			}
		}
		safetyIndexWeights <- road as_map (each::(each.weight*each.shapeLength));
		perimeterWeights<- road as_map (each::each.shape.perimeter);
    	if routingAlgorithm<="safest path"{//if selected routingAlgorithm is "safest path", then a graph is weighted based on safety indicies. Exclude roads restricted from driving, cycling and walking.
    		theGraph <- directed(as_edge_graph(road where (each.restriction<2))with_weights safetyIndexWeights);		
    	}else {//if routingAlgorithm is "shortest path", then a graph is weighted based on link perimeters.
    		theGraph <- directed(as_edge_graph(road where (each.restriction<2)));	
    	}
    	remove fileRoads from:self;
		write "Roads are created: "+ (machine_time - t2)/1000;
		
	}
	
    //Create species "counting stations"
	action createCountingStations{
		float t2 <- machine_time;
		create countingStation from: fileCountingStations with:[stationName::read("name")]{
			color <- #red;
		}
		//add real-world counting data to each counting station for further visualization
		matrix countsMatrix <- matrix(fileCounts);
		loop i from: 0 to: countsMatrix.rows-1{
			countingStation countSt <- one_of (countingStation where (each.stationName = "Elisabethkai"));
			add int(countsMatrix[1,i]) at:int(countsMatrix[0,i]) to:countSt.realCounts;
			countSt <- one_of (countingStation where (each.stationName = "Giselakai"));
			add int(countsMatrix[2,i]) at:int(countsMatrix[0,i]) to:countSt.realCounts;
			countSt <- one_of (countingStation where (each.stationName = "Rudolfskai"));
			add int(countsMatrix[3,i]) at:int(countsMatrix[0,i]) to:countSt.realCounts;
			countSt <- one_of (countingStation where (each.stationName = "Kaufmannsteg"));
			add int(countsMatrix[4,i]) at:int(countsMatrix[0,i]) to:countSt.realCounts;
		}
		remove fileCountingStations from:self;
		remove fileCounts from:self;
		write "Counting stations are created: "+ (machine_time - t2)/1000;
	}
	
	//Start counting of simulation time 
	reflex startSimulation when:cycle = 0{
		simulationStartTime <- machine_time;
	}
	
	//Save moving cyclists by activity type every "activeCylistsTimeInterval" cycle to csv file
	reflex saveActiveCyclists when: every(activeCylistsTimeInterval#cycle){
		save[
			cycle,
			length(people where(each.status = "moving")),
			length(people where(each.status = "moving" and each.activityType="home")),
			length(people where(each.status = "moving" and each.activityType="work")),
			length(people where(each.status = "moving" and each.activityType="business")),
			length(people where(each.status = "moving" and each.activityType="school")),
			length(people where(each.status = "moving" and each.activityType="university")),
			length(people where(each.status = "moving" and each.activityType="authority")),
			length(people where(each.status = "moving" and each.activityType="doctor")),
			length(people where(each.status = "moving" and each.activityType="recreation")),
			length(people where(each.status = "moving" and each.activityType="shop")),
			length(people where(each.status = "moving" and each.activityType="bringing")),
			length(people where(each.status = "moving" and each.activityType="other_place"))
		] to:activeCyclistsFileName type:csv rewrite:false;
	}
	
	//Save registered cyclists on a network by hour as a heatmap
	reflex saveHeatmap when:cycle = 1440{
		save road where(each.reversedRoad = nil) to: heatmapFileName type:"shp" crs:"EPSG:32633" rewrite:true attributes:[
			"linkId"::linkId,
			"brunnel"::brunnel,
			"baseType"::baseType,
			"bicycleInfrastructure"::bicycleInfrastructure,
			"designatedRoute"::designatedRoute,
			"roadCategory"::roadCategory,
			"maxSpeed"::maxSpeed,
			"pavement"::pavement,
			"widthLane"::widthLane,
			"gradient"::gradient,
			"numberLane"::numberLane,
			"oneway"::oneway,
			"restriction"::restriction,
			"shapeLength"::shapeLength,
			"safetyIndex"::safetyIndex,
			"hour_0"::cyclistsByHour[0],"hour_1"::cyclistsByHour[1],"hour_2"::cyclistsByHour[2],"hour_3"::cyclistsByHour[3],"hour_4"::cyclistsByHour[4],"hour_5"::cyclistsByHour[5],
			"hour_6"::cyclistsByHour[6],"hour_7"::cyclistsByHour[7],"hour_8"::cyclistsByHour[8],"hour_9"::cyclistsByHour[9],"hour_10"::cyclistsByHour[10],
			"hour_11"::cyclistsByHour[11],"hour_12"::cyclistsByHour[12],"hour_13"::cyclistsByHour[13],"hour_14"::cyclistsByHour[14],"hour_15"::cyclistsByHour[15],
			"hour_16"::cyclistsByHour[16],"hour_17"::cyclistsByHour[17],"hour_18"::cyclistsByHour[18],"hour_19"::cyclistsByHour[19],"hour_20"::cyclistsByHour[20],
			"hour_21"::cyclistsByHour[21],"hour_22"::cyclistsByHour[22],"hour_23"::cyclistsByHour[23],"hour_24"::cyclistsByHour[24],
			"cyclists"::cyclistsTotal
		];
		write "Heatmap is saved";
	}
	
	//Stop simulation at the end of a day(simulation)
	reflex stopSimulation when: cycle = 1440{
		write length(people where(each.status="moving")) ;
		write length(people);
		ask people where(each.status="moving"){
			do saveTrip;
		}
		write "Simulation is finished";	
		write "Total simulation time: " + (machine_time - simulationStartTime)/1000;
		do pause;
		do halt;
	}
}

//////////////////////////////////////////////////////////////////////////////SPECIES DECLARATION///////////////////////////////////////////////////////////////////////////////

//City border
species cityOutline;

//Home species hold residential information. A home has number of population by age group, employment status and current education status(number of currently enrolled pupils and students)
species home {
	string id;
	int HOME_POPULATION;
	int MALE_BELOW_5;int MALE_5_9;int MALE_10_14;int MALE_15_19;int MALE_20_24;int MALE_25_29;int MALE_30_34;int MALE_35_39;int MALE_40_44;int MALE_45_49;//example: number of male residents below 5 years old
	int MALE_50_54;int MALE_55_59;int MALE_60_64;int MALE_65_69;int MALE_70_74;int MALE_75_79;int MALE_80_84;int MALE_85_89;int MALE_90_94;int MALE_95_99;int MALE_over_100;
	int FEMALE_BELOW_5;int FEMALE_5_9;int FEMALE_10_14;int FEMALE_15_19;int FEMALE_20_24;int FEMALE_25_29;int FEMALE_30_34;int FEMALE_35_39;int FEMALE_40_44;int FEMALE_45_49;
	int FEMALE_50_54;int FEMALE_55_59;int FEMALE_60_64;int FEMALE_65_69;int FEMALE_70_74;int FEMALE_75_79;int FEMALE_80_84;int FEMALE_85_89;int FEMALE_90_94;int FEMALE_95_99;int FEMALE_over_100;
	int MALE_EMPLOYED;int MALE_UNEMPLOYED;int MALE_BELOW_15;int MALE_PENSIONERS;int MALE_PUPILS_STUDENTS_OVER_15;int MALE_INACTIVE;int MALE_UNKNOWN_EMPLOYMENT_STATUS;//number of residents by employment status
	int FEMALE_EMPLOYED;int FEMALE_UNEMPLOYED;int FEMALE_BELOW_15;int FEMALE_PENSIONERS;int FEMALE_PUPILS_STUDENTS_OVER_15;int FEMALE_INACTIVE;int FEMALE_UNKNOWN_EMPLOYMENT_STATUS;
	int PUPILS_6_14;int PUPILS_15_19;int STUDENTS;//number of residents by education status
	list<people> createdPeople;
	list<int>maleByAge;//list of male population by age group
	list<int>femaleByAge;//list of female population by age group
	aspect base{
		draw shape color:#transparent;
	}
	action createPeople{
		do createPerson(maleByAge,"male");
		do createPerson(femaleByAge,"female");
		
		//Assign employment status. "-1" means there is no min or max age restriction.
		do assignEmploymentStatus("below_15",MALE_BELOW_15,"male",0,14);
		do assignEmploymentStatus("below_15",FEMALE_BELOW_15,"female",0,14);
		do assignEmploymentStatus("pensioner",MALE_PENSIONERS,"male",-1,-1);
		do assignEmploymentStatus("pensioner",FEMALE_PENSIONERS,"female",-1,-1);
		do assignEmploymentStatus("pupils_students_over_15",MALE_PUPILS_STUDENTS_OVER_15,"male",15,-1);
		do assignEmploymentStatus("pupils_students_over_15",FEMALE_PUPILS_STUDENTS_OVER_15,"female",15,-1);
		do assignEmploymentStatus("employed",MALE_EMPLOYED,"male",15,104);
		do assignEmploymentStatus("employed",FEMALE_EMPLOYED,"female",15,104);
		do assignEmploymentStatus("unemployed",MALE_UNEMPLOYED,"male",15,104);
		do assignEmploymentStatus("unemployed",FEMALE_UNEMPLOYED,"female",15,104);
		do assignEmploymentStatus("inactive",MALE_INACTIVE,"male",15,104);
		do assignEmploymentStatus("inactive",FEMALE_INACTIVE,"female",15,104);
		do assignEmploymentStatus("undefined",MALE_UNKNOWN_EMPLOYMENT_STATUS,"male",0,104);
		do assignEmploymentStatus("undefined",FEMALE_UNKNOWN_EMPLOYMENT_STATUS,"female",0,104);
		
		//remove people under 6 years old, because of their inability to carry out activities and travel on their own.//remove people whose employment status is unknown.
		ask createdPeople where(each.age<6 and each.employmentStatus="below_15" or each.employmentStatus ="undefined"){
			remove self from:myself.createdPeople;do die;
		}
		
		/*Assign ongoing education status based on home species attributes "pupils_6_14", "pupils_15_19", "students".
		*6-14 and 15-19 age restrictions are fuzzy, since some students of compulsory education and higher educational institutions can be older or younger.
		*Pupils from 6 to 15 can be only unemployed. Pupils and studenst over 15 years old can be employed and unemployed. 
		*Umemployed pupils/students are those with employment status "pupils_students_over_15". Employed pupils/students are those with employment status "employed".
		*Calculation is based on a proportion of total numbers of pupils over 15("pupils_15_19") and students("students") taken from home species. 
		*People with employment status "pupils_students_over_15" are distributed as unemployed in the calculated proportion. The rest of potential pupils and students become employed.*/
		if createdPeople count(each.age<15)<PUPILS_6_14{
			PUPILS_6_14<-PUPILS_6_14-(PUPILS_6_14-people count(each.age<15));
			PUPILS_15_19<-PUPILS_15_19+(PUPILS_6_14-people count(each.age<15));
		}
		if PUPILS_15_19+STUDENTS<MALE_PUPILS_STUDENTS_OVER_15+FEMALE_PUPILS_STUDENTS_OVER_15{
			PUPILS_6_14<-PUPILS_6_14-((MALE_PUPILS_STUDENTS_OVER_15+FEMALE_PUPILS_STUDENTS_OVER_15)-(PUPILS_15_19+STUDENTS));
			PUPILS_15_19<-PUPILS_15_19+((MALE_PUPILS_STUDENTS_OVER_15+FEMALE_PUPILS_STUDENTS_OVER_15)-(PUPILS_15_19+STUDENTS));
		}
		do assignEmploymentStatus("pupil_6_14",PUPILS_6_14,"both",-1,-1);//assign "pupil" education status
		ask createdPeople where(each.employmentStatus="below_15"){employmentStatus<-"below_15_not_pupil";}
		if PUPILS_15_19!=0 or STUDENTS!=0{
			int pupils_15_19<- int((createdPeople count(each.employmentStatus="pupils_students_over_15")*PUPILS_15_19)/(PUPILS_15_19+STUDENTS));//number of potential unemployed pupils over 15 years old
			int students<- length(createdPeople where(each.employmentStatus="pupils_students_over_15"))-pupils_15_19;//number of potential unemployed students
			do assignEmploymentStatus("pupil_15_19",pupils_15_19,"both",-1,-1);//assign "pupil" education status
			do assignEmploymentStatus("student",students,"both",-1,104);//assign "student" education status
			do assignEmploymentStatus("employed_pupil",PUPILS_15_19-pupils_15_19,"both",-1,19);//assign "employed_pupil" education status
			do assignEmploymentStatus("employed_student",STUDENTS-students,"both",-1,104);//assign "employed_student" education status
		}
	}
	
	//Create people by gender. List "ageGroup" consists of number of people ordered by age group that reside on "myHome" geometry. One age group covers 5 years. 
	action createPerson(list<int>ageGroups,string groupGender){
		int ageMin<-0;//first age group is 0-4. These variables are updated with an increment of 5 years.
		int ageMax<-4;
		loop ag over:ageGroups{
			create people number:ag{
				age<-rnd(ageMin,ageMax);//randomly assign age between min and max values
				gender<-groupGender;
				homeLocation <- any_location_in(myself);//randomly assign home location from "myHome" geometry
				myHomeWithinCity <- homeLocation intersects cityOutline(0);//calculates whether home location is within city boundaries(true) or outside(false)
				location <- homeLocation;//place person at home location
				add self to:myself.createdPeople;
				speed<-0.0;
			}
			ageMin<-ageMin+5;//increment age range
			ageMax<-ageMax+5;
		}
	}
	
	//Assign employment status. "emStName" - type of employment status, "numberEmpSt" - number of people to assign with emp.st., "ageMin","ageMax" - age constraints.
	action assignEmploymentStatus(string empStName,int numberEmpSt,string theGender,int ageMin, int ageMax){
		list<people>listPeople;//list of selection of suitable people
		switch empStName{
			match "pensioner"{listPeople <- reverse(createdPeople where(each.employmentStatus = "" and each.gender=theGender) sort_by (each.age));}//suitable people are in the age order from 104 to 15
			match "pupils_students_over_15"{listPeople<- createdPeople where (each.employmentStatus = "" and each.gender = theGender and each.age >= ageMin) sort_by(each.age);}//suitable people are in the age order from 15 to 104
			match "pupil_6_14"{
				if numberEmpSt<createdPeople count(each.employmentStatus ="below_15"){//if number of people to assign status is less than total number of suitable people, then suitable people fare in the age order from 14 to 6
					listPeople <- reverse(createdPeople where(each.employmentStatus ="below_15")sort_by(each.age)); 
				}else{//if number of people to assign status is equal to or more than total number of suitable people, then suitable people are with employment status "below_15" or "pupils_students_over_15" sorted by age
					listPeople <- createdPeople where (each.employmentStatus = "below_15" or each.employmentStatus = "pupils_students_over_15") sort_by(each.age);
				}
				empStName<-"pupil";
			}
			match "pupil_15_19"{
				listPeople <- createdPeople where(each.employmentStatus="pupils_students_over_15") sort_by (each.age);//suitable people are with employment status "pupils_students_over_15" sorted by age
				empStName<-"pupil";
			}
			match "student"{listPeople <- createdPeople where(each.employmentStatus="pupils_students_over_15") sort_by (each.age);}//suitable people are with employment status "pupils_students_over_15" sorted by age
			match "employed_pupil"{listPeople<- createdPeople where(each.employmentStatus="employed") sort_by (each.age);}//suitable people are with employment status "employed" sorted by age
			match "employed_student"{listPeople<- shuffle(createdPeople where(each.employmentStatus="employed"));}//suitable people are with employment status "employed" sorted by age
			default{listPeople<-shuffle(createdPeople where (each.employmentStatus = "" and each.gender = theGender and each.age >= ageMin and each.age <= ageMax));}
		}
		people rndPerson;
		loop while:numberEmpSt!=0{
			rndPerson <- first(listPeople);
			rndPerson.employmentStatus <- empStName;
			listPeople<-listPeople-rndPerson;
			numberEmpSt<-numberEmpSt-1;
		}
		 /*Forbidden people to select activities that don't suit their employment status.
		  * There is one nuance: when "employed", "pupil" or "student" selects activity type, probabiilities for "work","business","school" and "university" are assumed as one common probability.*/
		ask rndPerson {
			if employmentStatus = "unemployed" or employmentStatus = "pensioner" or employmentStatus = "inactive_other" or employmentStatus = "below_15"{
				forbiddenActivities <- ["work","business","school","university"];
			}
		}
	}
}

/*People species represent moving objects. Restricted by probabilities and personal characteristics they are constantly assigned with daily activities. 
 * First they select activity type, then departure and duration times, then mode, speed and target location. 
 * Then they wait until departure time, travel, stop and stay at the activity location until duration time is over. Next, they select another type of activity and carry out the same procedure.
 * It is assumed that every time a person selects next activity, the is a chance to finish their daily plan, travel back home and stay there until the end of simulation.*/
species people skills:[moving] {
	int age;//possible values are 0-104
	string gender;//possible values are "male" and "female"
	string employmentStatus<-"";//possible values are "below_15", "pupil_student_over_15"(years old), "employed", "unemployed", "pensioner","inactive"(economically inactive, not registered as unemployed),"undefined"
	point homeLocation;//location of home
    bool myHomeWithinCity;//whether home of an agent is within city boundaries
    list<string>forbiddenActivities;//list of forbidden activities depending on employment status
    string status <- "staying";//possible values are "staying" or "moving"
    bool move<-false;//false - person does not move along the network but is transferred to target location for model simplification reasons; true - person moves along the network (when mode="bike", origin and/or destination are within the city boundaries
    list<float>activityProbabilities;//distribution of probabilities to select activity type depending on activity position (ordinal number of activity in activity chain)
    bool nextActivity<- false;//existance of next activity that person will carry out after finishing current activity
    bool lastActivity <- false;//when next activity is the last for a person in simulation
    point sourceLocation;//location of departure
    point targetLocation;//location of destination
    bool sourceWithinCity;//whether departure location is within a city or not
	bool targetWithinCity;//whether destination is within a city or not
    string activityType;//possible values are "home","other activity"(anything else than in the list),"work","business","school","university","shop","authority","doctor","recreation","bringing"(bringing children to kindergarden or children and old people to hospital)
    string activityTypePrev;//type of previous activity
    int startingTime<--9999;//time to start travelling, in min
    int endingTime<--9999;//time to stop activity, in min
    int durationTime<--9999;//time to spend at activity location, in min
	float travelTime<--9999.0;//time to spend on travelling, in min
	string mode<-"";//transport mode
	string oldMode;//transport mode that is replaced only for one trip while agent is not at home. It happens due to max distance limit, that person can travel with replaced mode to destination.
	bool changeMode;//whether mode has to be changed
	float maxDistance<-1000000.00;//maximum distance that can be travelled with a particular mode, in meters. Default value is 1000000.00 for "car", "car_passenger", "public_transport", "other_mode"
	float minDistance <-0.00;//minimum distance that can be travelled with particular mode, in meters.
    bool finished<- false;//whether agent is finished with current activity
	float activityDistance<-0.0;//travelled distance to activity location, in meters
	int activityId<--9999;//every assigned activity gets its ordinal number in list of performed activities
	list<road> traversedRoads;//roads that an agent passes
	int traversedIntersections<-0;//number of intersections that an agent passes
	float cityShare<-0.0;//percentage of trip within city boundaries, in %
	countingStation passedStation;//the last station that was passed during a trip
    string track_geom;//geometry values of all roads that people traverse within one trip
    aspect base {
        draw triangle(20) depth:rnd(2) color: rnd_color(255);
    }
    
	//Assign next activity based on distribution of activity probabilities
	action assignActivity(list<float>activityProbabilitiesList){
		string selectedActivityType <- selectActivityType(activityProbabilitiesList);//select activity type of next activity
		if selectedActivityType = ""{//if activity type is not selected, then an agent finishes its daily schedule and sets next activity to false.
			nextActivity <- false;
		}else{
			do assignDepartureTime(selectedActivityType);
			do assignDurationTime(selectedActivityType);
			if startingTime = -9999 or durationTime = -9999{//if starting or duration time is not selected, then an agent finishes its daily schedule and sets next activity to false.
				nextActivity<-false;
			}else{
				nextActivity<-true;
				activityTypePrev<- activityType;//type of previous activity is type of current activity
				activityType <- selectedActivityType;//activity type is a type of next activity
				do assignMode(selectedActivityType);
				do calculateMaxMinDistance;
				do calculateTarget(selectedActivityType);
				activityId<- activityId+1;//update activity position
			}
		}
		if nextActivity =false{//travel to home and be removed from simulation. If an agent is already at home, than it is simply removed.
			lastActivity<- true;//next activity is the last activity
			if activityType != "home"{
				nextActivity <- true;
				activityTypePrev<- activityType;
				activityType <- "home";//an agent is assigned to travel "home" as the last activity
				if activityId=0{
					do assignDepartureTime("home");
					do assignMode("home");
					do calculateMaxMinDistance;
				}else{
					startingTime <- cycle;//go home immediately
				}
				durationTime <- 1440-startingTime; //duration of stay at the last activity is until the end of the simulated day
				do calculateTarget("home");
				activityId <- activityId+1;
			}else{
				do die;
			}
		}
	}
		
	//Calculate activity type
	string selectActivityType(list<float>activityProbabilitiesList){
		//Recalculate activity probabilities list into probability distribution in regards to forbidden activities and previous activity. An agent cannot select the same activity type.
		activityProbabilities<-copy(activityProbabilitiesList);//update species variable activityProbabilities with global variable that hold information that is general for all agents
		if activityId != -9999{//if an agent has carried out an activity before next activity
			activityProbabilities[getActivityIndex(activityType)]<-0.0;
		}
		if forbiddenActivities !=[]{//if agent has forbidden activities, exclude their probabilities from the list
			loop forbiddenActivity over:forbiddenActivities{
				activityProbabilities[getActivityIndex(forbiddenActivity)]<-0.0;
			}
		}
		float newActivityProbability;
		float summOfProbabilities <- sum(activityProbabilities);
		loop index from:0 to:11 step:1{//loop through every value of the list (there are 12 values that relate to activity types and calculate probabilities distribution from 0.0% to 100.0%
			newActivityProbability <- newActivityProbability+activityProbabilities[index]*100/summOfProbabilities;
			activityProbabilities[index]<- newActivityProbability;
		}
		
		/*Select activity type according to distribution of probabilities. Probabilitiy values for "work","business","school","university" in a distribution can be selected by all "employed","pupils", and "students".
		 * When selected, depending on employment status of previously mention groups of people, a suitable type is assigned. Pupils that have selected "work" will be actually assigned with "school".*/
		float rndNumber1 <- rnd(last(activityProbabilities));
		switch rndNumber1{
			match_between[0.0,activityProbabilities[0]]{
				return"home";break;
			}
			match_between[activityProbabilities[0],activityProbabilities[1]]{
				return"other_place";break;
			}
			match_between[activityProbabilities[1],activityProbabilities[2]]{//"work" probability
				switch employmentStatus{
					match "pupil"{return "school";break;}
					match "student"{return "university";break;}
					match "employed"{return "work";break;}
					match "employed_pupil"{return "work";break;}
					match "employed_student"{return "work";break;}
				}
			}
			match_between[activityProbabilities[2],activityProbabilities[3]]{//"business" probability
				switch employmentStatus{
					match "pupil"{return "school";break;}
					match "student"{return "university";break;}
					match "employed"{return "business";break;}
					match "employed_pupil"{return "business";break;}
					match "employed_student"{return "business";break;}
				}
			}
			match_between[activityProbabilities[3],activityProbabilities[4]]{//"school" probability
				switch employmentStatus{
					match "pupil"{return "school";break;}
					match "student"{return "university";break;}
					match "employed"{return "work";break;}
					match "employed_pupil"{return "school";break;}
					match "employed_student"{return "school";break;}
				}
			}
			match_between[activityProbabilities[4],activityProbabilities[5]]{//"university" probability
				switch employmentStatus{
					match "pupil"{return "school";break;}
					match "student"{return "university";break;}
					match "employed"{return "work";break;}
					match "employed_pupil"{return "university";break;}
					match "employed_student"{return "university";break;}
				}
			}
			match_between[activityProbabilities[5],activityProbabilities[6]]{
				return "shop";break;
			}
			match_between[activityProbabilities[6],activityProbabilities[7]]{
				return "authority";break;
			}
			match_between[activityProbabilities[7],activityProbabilities[8]]{
				return "doctor";break;
			}
			match_between[activityProbabilities[8],activityProbabilities[9]]{
				return "recreation";break;
			}
			match_between[activityProbabilities[9],activityProbabilities[10]]{
				return "bringing";break;
			}
			default{return "";break;}
		}
	}
	
	//Calculate index of activity type in activity probabilities list
	int getActivityIndex(string activityTypeToExclude){
		switch activityTypeToExclude{
			match "home" {return 0;}
			match "other_place"{return 1;}
			match "work" {return 2;}
			match "business"{return 3;}
			match "school" {return 4;}
			match "university"{return 5;}
			match "shop" {return 6;}
			match "authority"{return 7;}
			match "doctor" {return 8;}
			match "recreation"{return 9;}
			match "bringing" {return 10;}
		}
	}
	
	//Calculate departure time depending on a type of next activity
	action assignDepartureTime(string selectedActivityType){
		startingTime<-0;
		list<float>startTimeProbability;//temporal list that holds selected distribution of probabilities
		int earliestTime;
		int latestTime;
		
		//Select probability distribution
		switch selectedActivityType{
			match "home"{startTimeProbability<-startTimeProbabilitiesHome[activityId];}
			match "school"{earliestTime<- 420; latestTime<- 480;}//departure time for "school" and "university" activities are randomly selected between min and max time
			match "university"{earliestTime<- 480; latestTime<- 1080;}
			match "work"{startTimeProbability<-startTimeProbabilitiesWork[activityId];}
			match "business"{startTimeProbability<-startTimeProbabilitiesBusiness[activityId];}
			match "recreation"{startTimeProbability<-startTimeProbabilitiesRecreation[activityId];}
			match "shop"{startTimeProbability<-startTimeProbabilitiesShop[activityId];}
			match "other_place"{startTimeProbability<-startTimeProbabilitiesOtherPlace[activityId];}
			match "authority"{startTimeProbability<-startTimeProbabilitiesAuthority[activityId];}
			match "doctor"{startTimeProbability<-startTimeProbabilitiesDoctor[activityId];}
			match "bringing"{startTimeProbability<-startTimeProbabilitiesBringing[activityId];}
			default{startingTime<--9999;}
		}
		
		//Select hour
		if startTimeProbability!=[]{
			float timeThreshold<-0.0;//threshold for time probability distribution in regards to current hour. Probabilities are given for all 24 hours. When a person calculates start time it takes into account probabilities for hours after current hour.
    		if cycle > 60{
    			timeThreshold <- startTimeProbability[int((cycle - (cycle mod 60))/60 )];
    		}
    		float rndNumberStartTime <- rnd(timeThreshold,100.00); //can choose probability between threshold value and 100%
    		if sum(startTimeProbability)>0{
    			switch rndNumberStartTime{
    				match_between [0.0,startTimeProbability[0]]{if cycle <=60{startingTime <- cycle + rnd(60-cycle);}break;}//probabiltiy for the hour between 00:00 - 01:00
    				match_between [startTimeProbability[0],startTimeProbability[1]]{earliestTime<-60;latestTime<-120;break;}//probabiltiy for the hour between 01:00 - 02:00...
    				match_between [startTimeProbability[1],startTimeProbability[2]]{earliestTime<-120;latestTime<-180;break;}
    				match_between [startTimeProbability[2],startTimeProbability[3]]{earliestTime<-180;latestTime<-240;break;}
    				match_between [startTimeProbability[3],startTimeProbability[4]]{earliestTime<-240;latestTime<-300;break;}
    				match_between [startTimeProbability[4],startTimeProbability[5]]{earliestTime<-300;latestTime<-360;break;}
    				match_between [startTimeProbability[5],startTimeProbability[6]]{earliestTime<-360;latestTime<-420;break;}
    				match_between [startTimeProbability[6],startTimeProbability[7]]{earliestTime<-420;latestTime<-480;break;}
    				match_between [startTimeProbability[7],startTimeProbability[8]]{earliestTime<-480;latestTime<-540;break;}
    				match_between [startTimeProbability[8],startTimeProbability[9]]{earliestTime<-540;latestTime<-600;break;}
    				match_between [startTimeProbability[9],startTimeProbability[10]]{earliestTime<-600;latestTime<-660;break;}	
    				match_between [startTimeProbability[10],startTimeProbability[11]]{earliestTime<-660;latestTime<-720;break;}
    				match_between [startTimeProbability[11],startTimeProbability[12]]{earliestTime<-720;latestTime<-780;break;}
    				match_between [startTimeProbability[12],startTimeProbability[13]]{earliestTime<-780;latestTime<-840;break;}
	    			match_between [startTimeProbability[13],startTimeProbability[14]]{earliestTime<-840;latestTime<-900;break;}
	    			match_between [startTimeProbability[14],startTimeProbability[15]]{earliestTime<-900;latestTime<-960;break;}
	    			match_between [startTimeProbability[15],startTimeProbability[16]]{earliestTime<-960;latestTime<-1020;break;}
	    			match_between [startTimeProbability[16],startTimeProbability[17]]{earliestTime<-1020;latestTime<-1080;break;}
	    			match_between [startTimeProbability[17],startTimeProbability[18]]{earliestTime<-1080;latestTime<-1140;break;}
	    			match_between [startTimeProbability[18],startTimeProbability[19]]{earliestTime<-1140;latestTime<-1200;break;}
	    			match_between [startTimeProbability[19],startTimeProbability[20]]{earliestTime<-1200;latestTime<-1260;break;}
	    			match_between [startTimeProbability[20],startTimeProbability[21]]{earliestTime<-1260;latestTime<-1320;break;}
	    			match_between [startTimeProbability[21],startTimeProbability[22]]{earliestTime<-1320;latestTime<-1380;break;}
	    			match_between [startTimeProbability[22],startTimeProbability[23]]{earliestTime<-1380;latestTime<-1440;break;}
	    			default{startingTime <- -9999;}
    			}
    		}else{startingTime<--9999;}
    	}
    	
    	//Calculate departure time
    	if cycle<=latestTime and startingTime != -9999{
    		if cycle>earliestTime{//select departure time between current time and latest time
    			startingTime <- cycle + rnd(latestTime-cycle);
    		}else{//select departure time between earliest time and latest time
    			startingTime <- earliestTime + rnd(60);
    		}
    	}else {startingTime <--9999;}//set departure time to null("-9999")
	}
     
    //Calculate duration time depending on a type of next activity
	action assignDurationTime(string selectedActivityType){
		int fixedDuration;//duration that does not vary
		int shortestDuration;//min duration
		int longestDuration;//max duration
		int closingTime;//closing time of facility based on activity type
		
		//Select min/max duration
		switch selectedActivityType{
			match "home"{shortestDuration<-30;longestDuration<-60;closingTime<-1440;}
			match "school"{//duration for "pupil" depends on age
				switch age{
					match_between [6,7]{fixedDuration<-300;closingTime<-960;}
					match_between [8,9]{fixedDuration<-420;closingTime<-960;}
					match_between [10,13]{fixedDuration<-480;closingTime<-960;}
					match_between [14,18]{shortestDuration<-360;longestDuration<-480;closingTime<-960;}
				}
			}
			match "university"{shortestDuration<-120;longestDuration<-360;closingTime<-1260;}
			match "work"{//duration for "employed" depends on gender and based on specific distribution of working hours 
				if gender = "male"{
    				float rndNumberMale<- rnd(99.9);
    				switch rndNumberMale{
    					match_between [0.0,3.0]{shortestDuration<-60;longestDuration<-132;closingTime<-1320;break;}
    					match_between [3.0,6.3]{shortestDuration<-144;longestDuration<-288;closingTime<-1320;break;}
    					match_between [6.3,10.2]{shortestDuration<-300;longestDuration<-420;closingTime<-1320;break;}
    					match_between [10.2,71.5]{shortestDuration<-432;longestDuration<-480;closingTime<-1320;break;}
    					match_between [71.5,96.7]{shortestDuration<-492;longestDuration<-708;closingTime<-1320;break;}
    					match_between [96.7,99.7]{shortestDuration<-720;longestDuration<-1020;closingTime<-1320;break;}
    					match_between [99.7,99.9]{shortestDuration<-60;longestDuration<-1020;closingTime<-1320;break;}
    				}
    			}else{
    				float rndNumberFemale<- rnd(100.0);
    				switch rndNumberFemale{
    					match_between [0.0,7.8]{shortestDuration<-60;longestDuration<-132;closingTime<-1320;break;}
    					match_between [7.8,27]{shortestDuration<-144;longestDuration<-288;closingTime<-1320;break;}
    					match_between [27,49.4]{shortestDuration<-300;longestDuration<-420;closingTime<-1320;break;}
    					match_between [49.4,89.7]{shortestDuration<-432;longestDuration<-480;closingTime<-1320;break;}
    					match_between [89.7,99.1]{shortestDuration<-492;longestDuration<-708;closingTime<-1320;break;}
    					match_between [99.1,99.9]{shortestDuration<-720;longestDuration<-1020;closingTime<-1320;break;}
    					match_between [99.9,100]{shortestDuration<-60;longestDuration<-1020;closingTime<-1320;break;}
    				}
    			}
			}
			match "business"{shortestDuration<-15;longestDuration<-180;closingTime<-1140;}
			match "recreation"{shortestDuration<-60;longestDuration<-180;closingTime<-1440;}
			match "shop"{shortestDuration<-15;longestDuration<-120;closingTime<-1140;}
			match "other_place"{shortestDuration<-15;longestDuration<-180;closingTime<-1440;}
			match "authority"{fixedDuration<-30;closingTime<-1140;}
			match "doctor"{fixedDuration<-60;closingTime<-1140;}
			match "bringing"{shortestDuration<-15;longestDuration<-60;closingTime<-1140;}
		}
		
		//Calculate duration
		int leftTime <- closingTime-60-startingTime; //left time until the place is closed - 60 min (for travel)
		if fixedDuration!=0{//calculate duration for activities with permanent duration depending time left until 1 hour before closing
			if leftTime>=fixedDuration{
				durationTime <- fixedDuration;
			}else if leftTime>=0{
				durationTime <- leftTime;
			}else{durationTime <- -9999;}
			
		}else{//calculate random duration depending time left until 1 hour before closing
			if leftTime>=longestDuration{
				durationTime <- shortestDuration + rnd((longestDuration - shortestDuration));
			}else if leftTime>=shortestDuration{
				durationTime <- shortestDuration + rnd((leftTime - shortestDuration));
			}else{durationTime <- -9999;}
		}
	}
    
	//Assign transport mode depending on a type of next activity
	action assignMode(string selectedActivityType){
		list<float>modeProbabilitiesList;//temporal list of mode probability distribution
		bool selectMode<-false;//when true mode has to be calculated
		if activityType="home" or mode=""{//if current activity is home, change mode for all next activities
			if changeMode=true{
				add mode to: oldModes;
				selectMode<-true;
			}else{
				if oldModes !=[]{//check list of modes that previously did not fit with distance requirements
					mode <- first(oldModes);//assign first mode in a list to mode for further activities
					remove first(oldModes) from: oldModes;//once it is been used, it needs to be removed from a list
				}else{
					selectMode<-true;//calculate mode normally
				}
			}
		}else{//if current activity is not home, change mode only for the next activity
			if changeMode=true{
				oldMode <- mode;
				if oldMode = "bike"{//if a replaced mode is bike, assign new mode "public_transport"
					mode <- "public_transport";
				}else {//if not take anything else
					selectMode<-true;
				}
			}else{
				if oldMode!=nil{
					mode<-oldMode;
				oldMode<-nil;
				}else{
					selectMode<-true;//calculate mode normally
				}
			}
		}
		if selectMode=true{
			int indexExtend;//index of modeProbabilities list that holds modal split values for city extend [0] and region extend [1]
			if sourceWithinCity = true{indexExtend<-0;}else{indexExtend<-1;}
			switch selectedActivityType{
				match "home" {loop modeProb over:modeProbabilitiesHome[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "other_place"{loop modeProb over:modeProbabilitiesOtherPlace[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "work"{loop modeProb over:modeProbabilitiesWork[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "business"{loop modeProb over:modeProbabilitiesBusiness[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "school"{loop modeProb over:modeProbabilitiesSchool[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "university"{loop modeProb over:modeProbabilitiesUniversity[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "shop"{loop modeProb over:modeProbabilitiesShop[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "authority"{loop modeProb over:modeProbabilitiesAuthority[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "doctor" {loop modeProb over:modeProbabilitiesDoctor[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "recreation"{loop modeProb over:modeProbabilitiesRecreation[indexExtend]{add modeProb to: modeProbabilitiesList;}}
				match "bringing" {loop modeProb over:modeProbabilitiesBringing[indexExtend]{add modeProb to: modeProbabilitiesList;}}
			}		
			float rndNumberMode <- rnd(100.00);
			switch rndNumberMode{
				match_between [0.0,modeProbabilitiesList[0]]{mode <- "walk";break;}
				match_between [modeProbabilitiesList[0],modeProbabilitiesList[1]]{mode <- "bike";break;}
				match_between [modeProbabilitiesList[1],modeProbabilitiesList[2]]{mode <- "car";break;}
				match_between [modeProbabilitiesList[2],modeProbabilitiesList[3]]{mode <- "car_passenger";break;}
				match_between [modeProbabilitiesList[3],modeProbabilitiesList[4]]{mode <- "public_transport";break;}
				match_between [modeProbabilitiesList[4],modeProbabilitiesList[5]]{mode <- "other_mode";break;}
			}
		}
	}
	
	//Calculate maximum and minimum distances based on distance probability distribution for "bike" and "walk". Other modes have fixed min/max distances. Calculate speed based on mode.
	action calculateMaxMinDistance{
		switch mode{
			match "walk"{
				switch rnd(100.00){
					match_between [0.0,70.9908735332464]{minDistance <- 0.00; maxDistance <- 1000.00;break;}
					match_between [70.9908735332464,100.00]{minDistance <- 1000.00; maxDistance <- 5000.00;break;}
				}
				do calculate_speed(0.16,3.1);//0.16-3.1 m/s
			}
			match "bike"{
				switch rnd(100.00){
					match_between [0.0,72.9672650475185]{minDistance <- 0.00; maxDistance <- 2000.00;break;}
					match_between [72.9672650475185,100.00]{minDistance <- 2000.00; maxDistance <- 8000.00;break;}
				}
				do calculate_speed(1.6,5.0);//1.6-5 m/s, 5.8-18 km/h
			}
			match "car"{minDistance <- 0.00;maxDistance<-1000000.0;do calculate_speed(3.3,13.3);}
			match "car_passenger"{minDistance <- 0.00;maxDistance<-1000000.0;do calculate_speed(3.3,13.3);}
			match "public_transport"{minDistance <- 0.00;maxDistance<-1000000.0;do calculate_speed(3.3,13.3);}
			match "other_mode"{minDistance <- 0.00;maxDistance<-1000000.0;do calculate_speed(0.16,16.5);}
		}
	}
	
	//Calculate source location  depending on a selected activity type
	action calculateInitialTarget(string selectedActivityType){
		facility rndFacility;
		switch selectedActivityType{
			match "home"{
				targetLocation <- homeLocation;
				targetWithinCity <- myHomeWithinCity;
			}
			match "work"{
				/*Selection of work facility is carried out in two steps. First, any work facility is randomly selected. 
				 * Secondly, its population value has to be higher than a random number generated between 0 and the highest population value of all work facilities.*/
				loop while:sourceLocation=nil{
					rndFacility <- shuffle(workFacilityList) first_with (each.facilityPopulation>0);//random facility has to be chosen from the list of facilities whose population is greater than 0
					if rndFacility.facilityPopulation > rnd(workFacilityList max_of (each.facilityPopulation)){
						targetLocation <- any_location_in(rndFacility);
						targetWithinCity <- sourceLocation intersects cityOutline(0); //calculate source location and its belonging to a city
						rndFacility.facilityPopulation <- rndFacility.facilityPopulation - 1;//decrease number of potential work places
					}
				}
			}
			default{
				rndFacility<- shuffle(facility) first_with (each.facilityType=selectedActivityType);// random facility based on activity type
				targetLocation <- any_location_in(rndFacility);
				targetWithinCity <- sourceLocation intersects cityOutline(0);
			}
		}
	}
	
	//Calculate target location depending on a selected activity type
	action calculateTarget (string selectedActivityType){
		facility rndFacility;//random facility
		if selectedActivityType="home"{
			targetLocation <- homeLocation;
			targetWithinCity <- myHomeWithinCity;
		}
		int maxPopulation<-workFacilityList max_of (each.facilityPopulation);
		loop while:targetLocation=nil{
			//Selection of random facility is carried out from a list of facility distances to which are within minimumDistance and maximumDistance defined by mode
			if  selectedActivityType="work"{
				//Selection of work facility has further conditions. Population value has to be higher than a random number generated between 0 and the highest population value of all work facilities.
				rndFacility <- shuffle(workFacilityList) first_with (each.facilityPopulation>0 and distance_to(sourceLocation,each.location)<=maxDistance and distance_to(sourceLocation,each.location)>minDistance);	
				if rndFacility!=nil{
					if rndFacility.facilityPopulation > rnd(maxPopulation){//workFacilityList max_of (each.facilityPopulation) - maximum population value
						rndFacility.facilityPopulation <- rndFacility.facilityPopulation - 1;//decrease number of potential work places
					}else{
						rndFacility<-nil;
					}
				}
			}else{
				rndFacility<- shuffle(facility) first_with (each.facilityType=selectedActivityType and distance_to(sourceLocation,each.location)<=maxDistance and distance_to(sourceLocation,each.location)>minDistance);
			}
			if rndFacility!=nil{//calculate target location and its belonging to a city
				changeMode<-false;
				targetLocation <- any_location_in(rndFacility);
				targetWithinCity <- targetLocation intersects cityOutline(0);
			}else{
				//Save current mode to an oldModes list if a person is at home or to an oldMode variable if not. Assign new mode.
				changeMode<-true;
				do assignMode(selectedActivityType);
				do calculateMaxMinDistance;//calculate max and min distances that are allowed to travel using new mode
			}
		}
	}	
	
	//Save trip with its attributes that has been done using "bike"
	action saveTrip{
		string delimeter<-";";//save as txt with ";" as a delimeter, since gama turn ; to , when saving it to csv format
		float sourceLocation_x;
		float sourceLocation_y;
		float targetLocation_x;
		float targetLocation_y;
		if sourceLocation!=nil{
			sourceLocation_x<-CRS_transform(sourceLocation).location.x;
			sourceLocation_y<-CRS_transform(sourceLocation).location.y;
		}
		if targetLocation!=nil{
			targetLocation_x<-CRS_transform(targetLocation).location.x;
			targetLocation_y<-CRS_transform(targetLocation).location.y;
		}
		bool female<-false;
		bool male<-false;
		if gender="female"{female<-true;} else{male <- true;}
		save
			string(self) + delimeter+
			string(activityId) + delimeter+
			string(finished)+delimeter+
			string(lastActivity)+delimeter+
			mode+delimeter+
			activityType+delimeter+
			string(startingTime)+delimeter+
			string(endingTime)+delimeter+
			string(durationTime)+delimeter+
			string(travelTime)+delimeter+
			string(speed)+delimeter+
			string(activityDistance)+delimeter+
			string(traversedIntersections)+delimeter+
			string(cityShare)+delimeter+
			track_geom+delimeter+
			string(sourceLocation_x)+delimeter+//coordinates x,y of source and target locations
			string(sourceLocation_y)+delimeter+
			string(targetLocation_x)+delimeter+
			string(targetLocation_y)+delimeter+
			string(sourceWithinCity)+delimeter+
			string(targetWithinCity)+delimeter+
			string(male)+delimeter+
			string(female)+delimeter+
			string(age)+delimeter
		 to:tripsFileName type:"text" rewrite:false;
	}
	
	//Assign initial activity. Initial activity has activityId equaled "0". This is where people start their day. Initial activity is saved after assignment.
	reflex assignFirstActivity when:cycle=0{
		activityType <- selectActivityType(activityProbabilities0);//select activity type of current activity
		do calculateInitialTarget(activityType);//calculate location of current activity that is a source location
		activityId<-0;	
		location<-targetLocation;	
		finished<-true;
		do saveTrip;
		finished<-false;
		sourceLocation<-targetLocation;
		targetLocation<-nil;
		endingTime<-0;
	}
	
	//Assigns next activity when current time is equal to an end time of current activity
	reflex assignNextActivity when:cycle = endingTime{ 
		endingTime<- -9999;
		switch activityId{//select list of activity probabilities depending on a position of current activity
			match 0{do assignActivity(activityProbabilities1);}
			match 1{do assignActivity(activityProbabilities2);}
			match 2{do assignActivity(activityProbabilities3);}
			match 3{do assignActivity(activityProbabilities4);}
			match 4{do assignActivity(activityProbabilities5);}
			match 5{do assignActivity(activityProbabilities6);}
			match 6{do assignActivity(activityProbabilities7);}
		}
	}
	
	//Update startMove variable depending locations of source and destination within a city or outside.
    reflex start when:cycle = startingTime and nextActivity =true{
    	if mode = "bike"{//people on bikes move in simulaited space
    		if targetWithinCity = false{
    			if sourceWithinCity = false{//when both source and  target locations are outside a city, calculate trip distance, travel time in advance, and  transfer an agent to its target location
    				location<-targetLocation;//change location to target location
    			}else{//when source location is within a city and target location is outside, let an agent move
    				move<-true;
    			}	
    		}else{//if target location is within a city and source locaiton is either within a city or not, let an agent move
    			move<-true;
    		}
    	}else{//people not on bikes are transferred directly to target locations without physically crossing the distance
    		location<-targetLocation;
    	}
    	nextActivity <- false;
    }
    
    //Move
    reflex move when:move=true{
    	status <- "moving";
		path pathFollowed <-  self goto (on:theGraph, target:targetLocation,move_weights: perimeterWeights, return_path:true);//move a person along a path every cycle. A path consists of segments. Segment represents geometry of a road
    	if pathFollowed!=nil{//register a person on traversed roads and counting stations
    		loop segment over:pathFollowed.segments{
    			road traversedRoad<-road(pathFollowed agent_from_geometry segment);
    			if traversedRoad!=last(traversedRoads){//traversed road is not yet registered
    				ask traversedRoad{
    					add self to:myself.traversedRoads;//save traversed road in a list
    					cyclists <- cyclists+1;//update road attribute of number of passed cyclists
    					if reversedRoad != nil{//if traversed road is part of two ways road, update variable "total number of cyclists" of reversed road
    						reversedRoad.cyclistsTotal <- reversedRoad.cyclistsTotal+1;
    					}else{cyclistsTotal <- cyclistsTotal+1;}//if a road does not have a reversed road, then update "total number of cyclists" of this road
    					roadWidth<- roadWidth + 0.005; //change road width for visualization purposes
    					roadColor <- #yellow;//change road color for visualization purposes
    				}
    				/*Find counting station that is nearby traversed road within 0.1m buffer and register a person at this station. 
    					 * Passed station variable helps to exclude unnecessary multiple registration at the same station.
    					 * This could have occured because there are few roads that are within 0.1 buffer. Since we don't know precise locations of stations on the network graph, we have to use a buffer. */
    				countingStation traversedStation;
    				ask traversedRoad{
    					traversedStation<-(countingStation at_distance 0.1) closest_to self;
    				}
    				if traversedStation!=nil and traversedStation!=passedStation{
    					traversedStation.cyclistsCurrent <- traversedStation.cyclistsCurrent+1;
    					passedStation <- traversedStation;//save traversed station to passed station variable
    				}
    			}
    		}
    	}
    }

	//Stop when an agent arrives at target location
    reflex stop when:location=targetLocation{
    	status <- "staying";
    	if move=true{//trips made by "bike" and intersect the city
    		do computeThePath(sourceLocation,targetLocation);//calculate distance,travel time, city share,itersections  on the path between source and target locations
    		endingTime <- cycle+durationTime;
    	}else{//trips made by all transport mode, and by "bike" when outside city boudaries
    		do calculateTravelTime(sourceLocation,targetLocation);//calculate travel time that is theoretically used to travel to the target
    		endingTime <- cycle+int(travelTime)+durationTime;
    	}
    	if lastActivity = true{endingTime <-1440;}//set ending time to end of simulation day
    	if endingTime<=1440{
    		finished <- true; 
    	}
    	do saveTrip;
    	move<-false;
    	finished <- false; 
		startingTime <- -9999;  
		durationTime <- -9999; 
		travelTime<- -9999.0;
		activityDistance<-0.0;
    	traversedIntersections<-0;
    	cityShare<-0.0;
		sourceLocation <- targetLocation;//current activity is next activity, source location of new next activity is target location of new current activity
		sourceWithinCity <- targetWithinCity;
		targetLocation <- nil;
		targetWithinCity <- nil;
		activityProbabilities<-[];//empty activityProbabilities variable
		track_geom<-nil;
    	passedStation<- nil;
    	if lastActivity = true or endingTime>1440{do die;}//remove a person from simulation
    }
    
 	//Calculate distance of trips when people are transferred to targets without physically crossing the distance
 	 action calculateTravelTime(point theSource1, point theTarget1){
		float dist;
		path computedPath <- path_between(theGraph, theSource1,theTarget1);//path between source and target locations. Path consists of segments(roads)
    	loop segment over:computedPath.segments{
    		ask road(computedPath agent_from_geometry segment){
    			dist <- dist+shapeLength;//trip distance
    		}
    	}
    	travelTime <-(dist/speed)/60.0;//calculate travel time depending on a speed
   	}
   	
 	//Calculate route, its length, length within a city and number of intersections when people move along network
    action computeThePath(point theSource1, point theTarget1){
    	list<geometry> track_links;
		road prevRoad<-nil;//previous road
		float lengthWithinCity<-0.0;//length of a route that is within a city
		path computedPath <- path_between(theGraph, theSource1,theTarget1);//path between source and target locations. Path consists of segments(roads)
    	loop segment over:computedPath.segments{
    		ask road(computedPath agent_from_geometry segment){
    			myself.activityDistance <- myself.activityDistance+shapeLength;//trip distance
    			if city=1{//if road is within city boundaries, add its length to lengthWithinCity
    				lengthWithinCity<-lengthWithinCity+shapeLength;
    			}
    			if prevRoad!=nil and prevRoad!=self{//calculate number of intersections
    				if (prevRoad.intersections=2 and self.intersections=2) 
    				or (prevRoad.intersections=2 and self.intersections=1)
    				or (prevRoad.intersections=1 and self.intersections=2)
    				or (prevRoad.intersectionId1=self.intersectionId1){
    					myself.traversedIntersections<-myself.traversedIntersections+1;
    				}
    			}
    			prevRoad<-self;
    			add CRS_transform(self.shape) to:track_links;//add geometry value of a road
    		}
    	}
    	cityShare<-lengthWithinCity*100/activityDistance;//calculate share of a route within a city
    	//calculate geometry of track from geometries of roads that cyclist traverses within one trip.
    	track_geom <- string(union(track_links));
    	travelTime <-(activityDistance/speed)/60.0;//calculate travel time depending on a speed
   	}
	
	//Calculate speed depending on selected mode, in m/s
	action calculate_speed(float min_speed, float offset){
		speed <- min_speed + rnd(offset);
	}
}

//Facility species represent places of various types for activities
species facility {
	string facilityType;
	int facilityPopulation;//number of people at a facility. Only work facilities have value of registered employees.
	rgb facilityColor;
	aspect base{
		draw shape color:facilityColor;
	}
}
	
//Road species represent directional and connected links that form street network. Attribute value "-9999" is a "null" value.
species road {
	int linkId;//id of a road given in input data
	road reversedRoad;//reversed road is the one that has opposite direction and a road that will keep information about passing people for both ways.
	int brunnel;//tunnel or bridge: "0"-no, "1"-yes
	string baseType;/*type of lane usage: 
	 * 1-Roadway, 2-bicycle path, 4-rail, 5-traffic island, 6-stairway, 7-side walk, 8-parking lane, 11-driving lane, 12-waterway, 13-uphill, 14-right turn lane, 21-protected pedestrian crossing,
	 * 22-bicycle crossing, 23-protected pedestrian and bicycle crossing, 24-tunnel, 25-bridge, 31-bike path with adjoining walkway, 32-multipurpose lanes, 33-bicycle lanes, 34-busway,
	 * 35-bicycle lane against the one-way, 36-pedestrian and bicycle path*/
	string bicycleInfrastructure;//type of bicycle infrastructure:"bicycle_way" - separated bicycle lane, "bicycle_lane" - bicycle lane adjacent to motorized lane, "mixed_way" - one lane for bicycles and motorized vehicles, "no" - no bicycle lane, only motorized lane.
	string bicycleInfrastructureFT;
	string bicycleInfrastructureTF;
	int mitVolume;//daily traffic volume of motorized vehicles per segment (24h).
	int mitVolumeFT;
	int mitVolumeTF;
	string designatedRoute;/*"planning"- road segments where planning authorities want bicyclists to ride; usually not available in standard data sets, must be obtain in workshops etc.
	 * "national" - highest category of designated routes, often along major rivers (in Austria e.g. Tauernradweg, Donauradweg etc.)
	 * "regional" - designated routes with major, regional impact, often realized as thematic routes (in Salzburg e.g. Mozartradweg)
	 * "local " - designated routes within municipalities/towns, often sponsored by local businesses (in Salzburg e.g. Raiffeisenradweg)
	 * "no" - no designated routes or planning intents*/
	string designatedRouteFT;
	string designatedRouteTF;
	string roadCategory;/*"primary" -  Highest category of roads witch are traversable by bicyclists (highways are excluded!). Mostly maintained by national/federal authorities and numbered (in Austria with prefix B),
	 * "secondary" - next highest category of roads. Mostly maintained by regional authorities and numbered (in Austria with prefix L). Within cities major roads which are not maintained by national/federal authorities should be of this category,
	 * "residential" - municipal roads which don’t belong to one of the 2 higher categories,
	 * "service" - all kinds of access and small connector roads where bicycles are permitted (e.g. Verbindungsweg, Zufahrt, Stichstraße etc.),
	 * "calmed" - roads with any kind of limited MIT access but bicycle permission (Begegnungszone, Wohnstraße, Anrainerstraßen, Wirtschaftswege etc.),
	 * "no_mit" - any roads with restricted MIT access but bicycle permission (pedestrian zone with bicycle permission, cycleway etc.),
	 * "path " - paths where cycling is either not permitted or not possible (although it is not explicitly restricted).*/
	int maxSpeed;//maximum speed allowed by regulations
	int maxSpeedFT;
	int maxSpeedTF;
	int adjacentEdge;//number of adjacent edges at the crossings
	int adjacentEdgeFT;
	int adjacentEdgeTF;
	string parking;//on street parking: "yes","no"
	string parkingFT;
	string parkingTF;
	string pavement;//"asphalt" - paved road, "gravel" - road with compacted gravel, "soft" - uncompacted path with soft underground, "cobble" - road with cobble stones
	int widthLane;//width of lane in meter
	int gradient;/*gradient category according to classification for upslope and downhill respective:
	-1.5 % <“0”<1,5 %; 1,5 % <“1”< 3 %; 3 % <“2”< 6 %; 6 % <“3”< 12 %; “4” > 12 %; -1,5 % >“-1”> -3 %; -3 % >“-2”> -6 %; -6 % >“-3”> -12 %; “-4” < -12 %*/
	int gradientFT;
	int gradientTF;
	string rails;//"yes","no"
	int numberLane;//number of lanes
	int numberLaneFT;
	int numberLaneTF;
	string landuse;/*"green" - areas that are not sealed and are “green” (open meadows, wood, pastures, parks etc.) or in “natural” condition (incl. water bodies etc.),
	 * "residential" - areas that are loosely covered with buildings (small towns and villages, single-family houses etc.),
	 * "built" - areas that are densely covered with buildings without/with little green spaces (cities, apartment buildings, multi-story buildings etc.),
	 * "commercial" - areas that are mainly covered by large commercial buildings (business parks etc.) */
	int oneway;//"0" - false (two ways), "1" - true (one way only)
	int onewayFT; //stands for availability of a way with direction From-To. If both directions are "0", then both ways. If one of directions is "0" and another one is "1", then one way.
	int onewayTF; //stands for availability of a way with direction To- From.
	int restriction; //"0" - not restricted, "1" - restricted for motorized vehicles, allowed to push bike, "2" - restricted for every type of mode
	int restrictionFT;
	int restrictionTF;
	float safetyIndex; //level of safety
	int intersectionId1;//intersection id at one of link ends.
	int intersectionId2;//intersection id at one of link ends
	int intersections;//number of intersections that a link has. "0" means that a link has no intersections with other links. "1" means that a link has 1 intersection with another link. In this case intersection ids of a link are the same. If intersection ids of one link are the same as intersection ids of another links, only then they share an intersection.
	int city;//location according to city boundaries. 0-outside city boundaries, 1-within city boundaries
	float shapeLength;//perimeter of a link
	float weight;//weight of a link, needed for calculation of routes. "perimeter" - for shortest path, "safety index" - for safest path
	int cyclists <- 0;//number of traversed cyclists over a course of simulation
	int cyclistsTotal <- 0;//number of traversed cyclists on both ways(if road has its reversed road)
	int cyclistsNumberPrev<-0;//saved number of traversed cyclists over the previous hour
	list<int> cyclistsByHour;//number of traversed cyclists every hour
	float roadWidth <- 1.0;//width of road in regard to number of traversed cyclists, used for visualization purpose
	rgb roadColor <-#dimgray;
	aspect base{
		draw shape color:roadColor width:roadWidth;
	}

	//Network assessment model calculates safety index according to set parameters
	action calculateSafetyIndex{
		list<float>indicators;
		list<float>weights<- [
			bicycleInfrastructureWeight,
			mitVolumeWeight,
			designatedRouteWeight,
			roadCategoryWeight,
			maxSpeedWeight,
			adjacentEdgeWeight,
			parkingWeight,
			pavementWeight,
			widthLaneWeight,
			gradientWeight,
			railsWeight,
			numberLaneWeight,
			landuseWeight
		];
		
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
		
		//Calculate index
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
			
		safetyIndex <-0.0;
		loop indicatorIndex2 from: 0 to: length (indicators) - 1 {
			safetyIndex <- safetyIndex + indicators[indicatorIndex2]*weights[indicatorIndex2];
		}
		
		//Convert
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
		if [14675,17391] contains linkId{}else{
		 	if linkId= 17367 {//Staatsbrücke bridge
		 		safetyIndex <- bridgeValue+1;
		 	} else if baseType !='' and baseTypeList contains 6{//Stairs
		 		safetyIndex<- pushValue*1.5;
		 	} else if (gradient > 1 or gradient < -1) and restriction = 1{//Slope with push requirement
		 		safetyIndex <- pushValue+abs(gradient)/1.5;
		 	} else if brunnel=1 and restriction =0{//Bridges
		 		safetyIndex <- bridgeValue;
		 	} else if brunnel=0 and restriction =1{
		 		safetyIndex <- pushValue;
		 	} else if brunnel =1 and restriction = 1{//Bridges with push requirement
		 		safetyIndex <- bridgeValue + (pushValue/1.5);
		 	}
		 }
		 safetyIndex <- safetyIndex with_precision 4;
	}
	
	//Update number of traversed cyclists every hour
    reflex updateCyclists when:every(60#cycle){
    	add cyclistsTotal-cyclistsNumberPrev to:cyclistsByHour;
    	cyclistsNumberPrev<-cyclistsTotal;
    }
}

//Counting stations which register passing cyclists for validation of the model
species countingStation{
	rgb color;
	string stationName;
	int cyclistsCurrent<-0;//total number of passed cyclists so far
	int cyclistsPrev <-0;//total number of passed cyclists at previous "countingStationTimeInterval"
	int cyclists<-0;//number of passed cyclists for the last "countingStationTimeInterval" cycles
	map<int,int> realCounts;//number of passed cyclists from real-world data
	aspect base{
		draw shape color:color;
	}
	
	//Save number of cyclists passed counting stations every "countingStationTimeInterval" of cycles(min)
	reflex saveCoutningData when: every(countingStationTimeInterval#cycle){
		cyclists <- cyclistsCurrent-cyclistsPrev;
		save [cycle,stationName,cyclists] to:countsFileName type:"csv" rewrite:false;
		cyclistsPrev <- cyclistsCurrent;//save total number of cyclists that passed the station
		if time=1440 #mn{write "The last counting data has been saved";}	
	}
}

//////////////////////////////////////////////EXPERIMENT///////////////////////////////////////////////////////////////////////////////

experiment bicycle_model type:gui{
	parameter "show facilities" var: showFacility <- "none" among:["none","home","work","university","school","educational_institution","shop","recreation","kindergarden","other_place"] category:"Facility";
	parameter "choose routing algorithm" var: routingAlgorithm <- "safest path" among:["safest path","shortest path"] category:"Network";
	output{
		display cityDisplay type:opengl background:rgb(10,40,55){
			species facility aspect:base;
			species road aspect:base;
			species people aspect: base;
			species countingStation aspect:base;
		}
		
		display activeAgents type:java2D refresh:every(10#cycle){
			chart "Total number of active cyclists" type: series size: {1, 0.5} position: {0,0}{
				data "Active cyclists" value: people count (each.status="moving") style:line color:#black;
			}
			chart "Active cyclists by trip purpose" type: series size: {1, 0.5} position: {0, 0.5}{
				data "School" value: people count (each.status="moving" and each.activityType="school") style:line color:#mediumseagreen;
				data "University" value: people count (each.status="moving" and each.activityType="university") style:line color:#plum;
				data "Work" value: people count (each.status="moving" and each.activityType="work") style:line color:#royalblue;
				data "Recreation" value: people count (each.status="moving" and each.activityType="recreation") style:line color:#khaki;
				data "Shop" value: people count (each.status="moving" and each.activityType="shop") style:line color:#chocolate;
				data "Other activity" value: people count (each.status="moving" and each.activityType="other_place") style:line color:#darkcyan;
				data "Home" value: people count (each.status="moving" and each.activityType="home") style:line color:#cadetblue;
				data "Business" value: people count (each.status="moving" and each.activityType="business") style:line color:#maroon;
				data "Authority" value: people count (each.status="moving" and each.activityType="authority") style:line color:#darkgrey;
				data "Doctor" value: people count (each.status="moving" and each.activityType="doctor") style:line color:#coral;
				data "Bringing" value: people count (each.status="moving" and each.activityType="bringing") style:line color:#seagreen;
			}
		}
		
		display populationCharacteistics type:java2D refresh:false{
			chart "Population by employment status"  size: {0.5,0.5} position: {0, 0} type:pie{
				data "employed" value:(people count (each.employmentStatus = "employed")) color:°red;
				data "unemployed" value:(people count (each.employmentStatus = "unemployed")) color:°green;
				data "incative student" value:(people count (each.employmentStatus = "student")) color:°blue;
				data "incative other" value:(people count (each.employmentStatus = "inactive_other")) color:°yellow;
				data "pensioner" value:(people count (each.employmentStatus = "pensioner")) color:°grey;
				data "undefined" value:(people count (each.employmentStatus = "undefined")) color:°lime;
				data "below 15" value:(people count (each.employmentStatus = "below_15")) color:°orange;
			}
			chart "Population by gender"  size: {0.5,0.5} position: {0.5, 0} type:pie{
				data "male" value:(people count (each.gender = "male")) color:°blue;
				data "female" value:(people count (each.gender = "female")) color:°red;
			}
			chart "Population by age group"   size: {1.0,0.5} position: {0, 0.5} type:histogram{
				map<string, int> age_distribution;
				add people count (each.age >=0 and each.age <=9) at: "age_0_9" to: age_distribution;
				add people count (each.age >=10 and each.age <=19) at: "age_10_19" to: age_distribution;
				add people count (each.age >=20 and each.age <=29) at: "age_20_29" to: age_distribution;
				add people count (each.age >=30 and each.age <=39) at: "age_30_39" to: age_distribution;
				add people count (each.age >=40 and each.age <=49) at: "age_40_49" to: age_distribution;
				add people count (each.age >=50 and each.age <=59) at: "age_50_59" to: age_distribution;
				add people count (each.age >=60 and each.age <=69) at: "age_60_69" to: age_distribution;
				add people count (each.age >=70 and each.age <=79) at: "age_70_79" to: age_distribution;
				add people count (each.age >=80 and each.age <=89) at: "age_80_89" to: age_distribution;
				add people count (each.age >=90) at: "age_90_over" to: age_distribution;
				datalist age_distribution.keys  value: age_distribution.values ;	
			}
		}
		
		display activeAgentsAtStations15Min type:java2D refresh:every(15#cycle){
			chart "Active cyclists at Rudolfskai per 15 min" type: series size: {0.5, 0.3} position: {0, 0}{
				data "simulated counts" value: countingStation(0).cyclists style:line color:#goldenrod;
				data "real counts" value: countingStation(0).realCounts[cycle] style:line color:#gamablue;
			}
			chart "Active cyclists at Kaufmansteg per 15 min" type: series size: {0.5, 0.3} position: {0,0.5}{
				data "simulated counts" value: countingStation(1).cyclists style:line color:#goldenrod;
				data "real counts" value: countingStation(1).realCounts[cycle] style:line color:#gamablue;
			}
			chart "Active cyclists at Giselakai per 15 min" type: series size: {0.5, 0.3} position: {0.5,0}{
				data "simulated counts" value: countingStation(2).cyclists style:line color:#goldenrod;
				data "real counts" value: countingStation(2).realCounts[cycle] style:line color:#gamablue;
			}
			chart "Active cyclists at Elisabethkai per 15 min" type: series size: {0.5, 0.3} position: {0.5,0.5}{
				data "simulated counts" value: countingStation(3).cyclists style:line color:#goldenrod;
				data "real counts" value: countingStation(3).realCounts[cycle] style:line color:#gamablue;
			}
		}
	}
}
