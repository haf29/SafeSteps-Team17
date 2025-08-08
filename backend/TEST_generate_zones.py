
#from dotenv import load_dotenv
#load_dotenv()
from api.services.h3_utils import generate_zone_ids
# type : featurecollection
#features [
#type : feature
#properties:{name:beirut}
#geometry :{
#type:polygon
#coordinates:[...]}}]
beirut = {
    "type": "Polygon",
    "coordinates": [[
        [35.59162498298079, 33.940065201128334],
        [35.572005518255196, 33.90490653187199],
        [35.46987428475077, 33.90028936404184],
        [35.480332490494646, 33.79608579493343],
        [35.52212339964245, 33.82114173341516],
        [35.550877998954945, 33.85122835122202],
        [35.59162498298079, 33.940065201128334]
    ]]
}

zones = generate_zone_ids(beirut, 9)
print("Sample zone IDs:", zones[:5], "… total:", len(zones))
