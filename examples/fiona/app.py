import fiona
import shapely
from osgeo import gdal
from shapely.geometry import Point, mapping

gdal.UseExceptions()

print(f"fiona {fiona.__version__} | GDAL do fiona: {fiona.__gdal_version__} | GDAL da imagem: {gdal.__version__}")

schema = {"geometry": "Point", "properties": {"name": "str"}}
with fiona.open("/tmp/points.gpkg", "w", driver="GPKG", schema=schema, crs="EPSG:4326") as dst:
    dst.write({"geometry": mapping(Point(-45.0, -5.0)), "properties": {"name": "exemplo"}})

with fiona.open("/tmp/points.gpkg") as src:
    print(f"GeoPackage gravado e relido com {len(src)} feição(ões); shapely {shapely.__version__}")
