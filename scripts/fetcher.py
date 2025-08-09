import geopandas as gpd
import h3
import json
import os
from shapely.geometry import Polygon, MultiPolygon, mapping
from backend.api.services import h3_utils as hh


# Load the GeoBoundaries GeoJSON file
script_dir = os.path.dirname(__file__)
geojson_path = os.path.join(script_dir, "..", "data", "LBN_ADM2.geojson")
gdf = gpd.read_file(geojson_path)
#file is long-lat, coords in result is long-lat
def generate_zone_ids(geometry, resolution=9):
    if geometry.is_empty:
        return []

    zone_ids = set()

    if isinstance(geometry, MultiPolygon):
        for poly in geometry.geoms:
            zone_ids.update(generate_zone_ids(poly, resolution))
        return list(zone_ids)

    if isinstance(geometry, Polygon):
        #Convert Shapely Polygon to GeoJSON-style dict with lon-lat
        polygon_geojson = {
            "type": "Polygon",
            "coordinates": [hh.lonlat_to_latlon(list(geometry.exterior.coords))]
        }

        try:
            zone_ids.update(h3.polyfill(polygon_geojson, resolution))
        except Exception as e:
            print(f"Failed H3 conversion: {e}")

    return list(zone_ids)

features = []

for _, row in gdf.iterrows():
    name = row.get('shapeName') or row.get('NAME_2') or "Unknown"
    geometry = row['geometry']

    if geometry is None or geometry.is_empty:
        continue

    try:
        zone_ids = generate_zone_ids(geometry, resolution=9)

        feature = {
            "type": "Feature",
            "properties": {
                "name": name,
                "zone_ids": zone_ids
            },
            "geometry": mapping(geometry)
        }
        features.append(feature)
    except Exception as e:
        print(f"Error processing {name}: {e}")

geojson_output = {
    "type": "FeatureCollection",
    "features": features
}

#Save to file by writing result
output_path = os.path.join("data", "cities.json")
with open(output_path, "w") as f:
    json.dump(geojson_output, f)

print("Saved to 'lebanon_districts_with_h3.geojson'")
