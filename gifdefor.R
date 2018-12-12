#!/usr/bin/Rscript

# ==============================================================================
# author          :Ghislain Vieilledent
# email           :ghislain.vieilledent@cirad.fr, ghislainv@gmail.com
# web             :https://ghislainv.github.io
# license         :GPLv3
# ==============================================================================

##= Libraries
list.of.packages = c("rgdal","sp","raster","rgrass7","dataverse","glue")
new.packages <- list.of.packages[!(list.of.packages %in% installed.packages()[,"Package"])]
if(length(new.packages) > 0) {install.packages(new.packages)}
lapply(list.of.packages, require, character.only=T)

##=====================================
## Create new grass location in UTM 38S
# dir.create("grassdata")
# system("grass72 -c epsg:32738 grassdata/gifdefor")  # Ignore errors

## Connect R to grass location
## Make sure that /usr/lib/grass72/lib is in your PATH in RStudio
## On Linux, find the path to GRASS GIS with: $ grass72 --config path
## It should be somethin like: "/usr/lib/grass72"
## On Windows, find the path to GRASS GIS with: C:\>grass72.bat --config path
## If you use OSGeo4W, it should be: "C:\OSGeo4W\apps\grass\grass-7.2"
Sys.setenv(LD_LIBRARY_PATH=paste("/usr/lib/grass72/lib", 
																 Sys.getenv("LD_LIBRARY_PATH"),sep=":"))

## Initialize GRASS
initGRASS(gisBase="/usr/lib/grass72",home=tempdir(), 
					gisDbase="grassdata",
					location="gifdefor",mapset="PERMANENT",
					override=TRUE)

# ================================================
# Import forest rasters
# ================================================

Year <- c(1953,1973,1990,2000,2010,2017)
for (i in 1:length(Year)) {
	cat(glue("Processing year {Y}\n"))
	Y <- Year[i]
  in_file <- glue("gisdata/raster/forest_cover/for{Y}.tif")
  out_name <- glue("for{Y}")
  pars <- list(input=in_file, output=out_name)
  execGRASS("r.in.gdal", flags=c("overwrite"), parameters=pars)
}

# ================================================
# Rasterize and import Madagascar boundaries
# ================================================

# Import
pars <- list(input="gisdata/vector/mada", layer="mada38s", output="mada")
execGRASS("v.in.ogr", flags=c("overwrite"), parameters=pars)
# Set region
execGRASS("g.region", flags=c("a","p"), parameters=list(raster="for2000"))
# Rasterize
pars <- list(input="mada", type="area", use="val", value=0L, 
						 output="mada", memory=1000L)
execGRASS("v.to.rast", flags=c("overwrite"), parameters=pars)

# ================================================
# Import waterbodies
# ================================================

# Create output directory
dir.create("output")

## Raster of water-bodies over Madagascar
# Region
Extent <- "298440 7155900 1100820 8682420"
Res <- "30"
proj.s <- "EPSG:4326"
proj.t <- "EPSG:32738"
Input <- "output/water.vrt"
Output <- "output/water.tif"
# gdalbuildvrt
system("gdalbuildvrt -overwrite output/water.vrt gisdata/raster/waterbodies/*.tif")
# gdalwarp
system(paste0("gdalwarp -overwrite -s_srs ",proj.s," -t_srs ",proj.t," -te ",Extent,
							" -tr ",Res," ",Res," -r near -ot Byte -co 'COMPRESS=LZW' -co 'PREDICTOR=2' ",Input," ",Output))
# Import
pars <- list(input="output/water.tif", output="water")
execGRASS("r.in.gdal", flags=c("overwrite"), parameters=pars)

# ================================================
# Combine maps
# ================================================

for (i in 1:length(Year)) {
	cat(glue("Processing year {Y}\n"))
	Y <- Year[i]
	expr <- glue("for{Y}c = if(!isnull(for{Y}), for{Y}, \\
						 if(!isnull(water) &&& !isnull(mada) \\
						 &&& water>0, 2, if(!isnull(mada), 0, null())))")
	execGRASS("r.mapcalc", flags=c("overwrite"), expression=expr)
}

# Colors rules
# grey, #d0d0d0, 208 208 208
# green, #4a812e, 74 129 46
# blue, #2a6ad6, 42 106 214
# black, #2d312c, 45 49 44

col0 <- "0 208:208:208"
col1 <- "1 74:129:46"
col2 <- "2 42:106:214"
#col3 <- "5 120:120:120"
col3 <- "5 208:208:208"
colnv <- "nv 255:255:255"
fileConn <- file("gisdata/color_rules1.txt")
writeLines(c(col0,col1,col2,col3,colnv), fileConn)
close(fileConn)

# Set color palette
for (i in 1:length(Year)) {
	Y <- Year[i]
  execGRASS("r.colors", map=glue("for{Y}c"),
  					rules="gisdata/color_rules1.txt")
}

# Export 1km
execGRASS("g.region", flags=c("a","p"), res="1000")
for (i in 1:length(Year)) {
	cat(glue("Processing year {Y}\n"))
	Y <- Year[i]
	execGRASS("r.out.gdal", flags="overwrite",
						input=glue("for{Y}c"), createopt="compress=lzw,predictor=2", 
						type="Byte", output=glue("output/for{Y}c.tif"))
	
}
execGRASS("g.region", flags=c("a","p"), raster="for2000")

# PNG
execGRASS("g.region", flags=c("a","p"), res="1000")
for (i in 1:length(Year)) {
	Y <- Year[i]
	execGRASS("r.out.png", flags="overwrite",
						input=glue("for{Y}c"), output=glue("output/for{Y}c.png"))
}
execGRASS("g.region", flags=c("a","p"), raster="for2000")

# GIF
for (i in 1:length(Year)) {
	Y <- Year[i]
  system(glue("convert -pointsize 72 -gravity North -draw \"text \\
						  0,0 '{Y}'\" output/for{Y}c.png output/for{Y}c.gif"))
}
system("convert -delay 200 -loop 0 output/*c.gif output/gifdefor.gif")

# ================================================
# Shaded relief
# ================================================

# Import elevation
in_file <- "gisdata/raster/elevation/elevation.tif"
pars <- list(input=in_file, output="elevation")
execGRASS("r.in.gdal", flags=c("overwrite"), parameters=pars)

# Compute relief
execGRASS("g.region", flags=c("a","p"), res="1000")
pars <- list(input="elevation", output="relief")
execGRASS("r.relief", flags=c("overwrite"), parameters=pars)
# PNG
execGRASS("r.out.png", flags="overwrite",
					input="relief", output="output/relief.png")
# TIF
execGRASS("r.out.gdal", flags="overwrite",
					input="relief", createopt="compress=lzw,predictor=2", 
					type="Byte", output=glue("output/relief.tif"))
execGRASS("g.region", flags=c("a","p"), raster="for2000")

# Shaded raster
for (i in 1:length(Year)) {
	Y <- Year[i]
	cat(glue("Processing year {Y}\n"))
  pars <- list(shade="relief", color=glue("for{Y}c"),
  						 output=glue("for{Y}c_shade"))
  execGRASS("r.shade", flags=c("overwrite"), parameters=pars)
}

# PNG
execGRASS("g.region", flags=c("a","p"), res="1000")
for (i in 1:length(Year)) {
	Y <- Year[i]
	execGRASS("r.out.png", flags="overwrite",
						input=glue("for{Y}c_shade"), output=glue("output/for{Y}c_shade.png"))
}
execGRASS("g.region", flags=c("a","p"), raster="for2000")

# GIF
for (i in 1:length(Year)) {
	Y <- Year[i]
	system(glue("convert -pointsize 72 -gravity North -draw \"text \\
							0,0 '{Y}'\" output/for{Y}c_shade.png output/for{Y}c_shade.gif"))
}
system("convert -delay 200 -loop 0 output/*c_shade.gif output/gifdefor_shade.gif")

# ================================================
# Use of ggplot2 for hill shade
# ================================================

require(raster)
require(ggplot2)

# Load rasters
for2000 <- raster("output/for2000c.tif")
hill <- raster("output/relief.tif")

#	Convert rasters to dataframes for plotting with ggplot
hdf <- rasterToPoints(hill); hdf <- data.frame(hdf)
colnames(hdf) <- c("X","Y","Hill")
ddf <- rasterToPoints(for2000); ddf <- data.frame(ddf)
colnames(ddf) <- c("X","Y","For")

# Colors
col0 <- "#d0d0d0" # 208 208 208
col1 <- "#4a812e" # 74 129 46
col2 <- "#2a6ad6" # 42 106 214

#	Plot hillShade layer with ggplot()
p <- ggplot(NULL, aes(X, Y)) +
	geom_raster(data=ddf, aes(fill=factor(For))) +
	scale_fill_manual(values=c(col0,col1,col2),
										na.value="transparent", guide="none") +
	geom_raster(data=hdf,aes(alpha=Hill)) +
	scale_alpha(range=c(0,0.7), guide="none") +
	theme_minimal() +
	coord_equal()
print(p)
ggsave("output/for2000_shade_ggplot.pdf", p)

# End