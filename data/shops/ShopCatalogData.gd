# res://data/shops/ShopCatalogData.gd
extends Resource
class_name ShopCatalogData

# Season mapping:
#  -1 = Any season
#   0 = Sunwake
#   1 = Duskhaven
@export var shop_id: String = "GeneralStore"
@export var season: int = -1

@export var entries: Array[ShopCatalogEntry] = []
