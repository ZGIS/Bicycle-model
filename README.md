# Bicycle-model

The purpose of the model is to generate disaggregated traffic flow distribution of cyclists at the regional scale level. The model is fuelled by statistical and topographical data as well as by generalized assumptions derived from survey data on mobility behaviour. It results in emergent flow patterns at a high spatial and temporal level of detail.

The model runs on GAMA-platform, which is a modeling and simulation development environment for building spatially explicit agent-based simulations.

# Getting started

## Installing
Dowload GAMA-platform (GAMA1.7RC2 version) from https://gama-platform.github.io/. This platform requires to install Java 1.8 and minimum of 4 GB of RAM.

After installation set up the maximum memory allocated to GAMA to at least 8 GB. It is possible through GAMA menu in Help -> Preferences -> Interface. Make sure GAMA uses the same coordinate reference system as the input shapefiles (EPSG:32633) in Help -> Preferences -> Data and Operators.

The repository has a folder named "code" which holds gama project files. Import these files into GAMA by right-clicking on User-models in Models tab of GAMA interface. Select GAMA project. In new window browse to "code" folder as a root directory. Make sure to check the box "Copy project into workspace". Click Finish.

## Running experiment

Project consists of input data in "includes" and model code in "models". 

Before running model code there is an option to parameterize routing algorithm by selecting either "shortest path" or "safest path" (default). Another parameter is responsible for visualization of facilities on display by type.

After model run output data is saved in "output_data" folder in "includes".

Model initialization takes approximately 1 h and simulation runs approximately 3 h. For better performance it is better to close display windows with output graphs and diagrams after initialization.

## Documentation

ODD protocol can be found in "docs".

## Authors

Dana Kaziyeva, Gudrun Wallentin, Martin Loidl

## Licence

Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License (http://creativecommons.org/licenses/by-nc-sa/4.0/)

## Acknowledgements

The model is built on GAMA toy model "Simple traffic model" by Patrick Taillandier and extends "Salzburg Bicycle Model" by Gudrun Wallentin and Martin Loidl (Wallentin, Gudrun (2016, October 29). “Salzburg Bicycle model” (Version 1.0.0). CoMSES Computational Model Library. Retrieved from: https://www.comses.net/codebases/5259/releases/1.0.0/)
