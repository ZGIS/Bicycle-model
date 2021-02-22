# Bicycle-model

The purpose of the model is to generate the spatio-temporal distribution of bicycle traffic flows at a regional scale level. Disaggregated results are computed for each network segment with the minute time step. The human decision-making is governed by probabilistic rules derived from the mobility survey. The model uses demographical data, employment data, mobility survey data, points of interest dataset, and a network.

The model runs on GAMA-platform (Taillandier et.al. 2019), which is a modeling environment for building spatially explicit agent-based simulations.

# Getting started

## Installing

Download the GAMA-platform (GAMA1.8 with JDK version) from https://gama-platform.github.io/. The platform requires a minimum of 4 GB of RAM.

After installation set up the maximum memory allocated to the GAMA to at least 4 GB. It is possible through the GAMA menu in Help -> Preferences -> Interface. Make sure the platform uses the same coordinate reference system as the input shapefiles (EPSG:32633) in Help -> Preferences -> Data and Operators.

The download zip has the “code” folder with the GAMA project files. Import these files into the GAMA by right-clicking on the “User-models” in the “Models” tab of the GAMA interface. Select the “GAMA project”. In the new window browse to the “code” folder as a root directory. Make sure to check the boxes “Search for nested projects” and “Copy project into workspace”. Click Finish.

## Running experiment

The input data of the project is in the “includes” folder and the model code in the “models” folder under “bicycle_model.gaml” name.

Before running the model code there is an option to parameterize the routing algorithm by selecting either the “shortest path” or “safest path” (default). The rest of the parameters is used to set the weights for bikability index calculation.

During a simulation output data are saved under the following path: “includes/output_data/”.

The model initialization takes approximately 1-3 min and the simulation runs approximately 40-60 min. For better performance switch off the displays by clicking “x” after the initialization or comment out the display code block in the experiment section of the code before running an experiment.

## Documentation

ODD protocol can be found in "docs".

## Authors

Dana Kaziyeva, Gudrun Wallentin, Martin Loidl

## Licence

Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License (https://creativecommons.org/licenses/by-nc-sa/4.0/)

## Associated publications

Kaziyeva, D.; Loidl, M.; Wallentin, G. Simulating Spatio-Temporal Patterns of Bicycle Flows with an Agent-Based Model. ISPRS Int. J. Geo-Inf. 2021, 10, 88. https://doi.org/10.3390/ijgi10020088

## Acknowledgements

The model extends "Salzburg Bicycle Model" by Gudrun Wallentin and Martin Loidl (Wallentin 2016)

## References

Taillandier, P.; Gaudou, B.; Grignard, A.; Huynh, Q.-N.; Marilleau, N.; Caillou, P.; Philippon, D.; Drogoul, A. Building, composing and experimenting complex spatial models with the GAMA platform. GeoInformatica 2019, 23, 299–322, doi:10.1007/s10707-018-00339-6.

Gudrun Wallentin (2016, October 29). “Salzburg Bicycle model” (Version 1.0.0). CoMSES Computational Model Library. Retrieved from: https://www.comses.net/codebases/5259/releases/1.0.0/
