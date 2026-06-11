extends Resource
class_name HelpBookData

@export var pages: Array[HelpBookPageData] = []


func get_unlocked_pages() -> Array[HelpBookPageData]:
	var out: Array[HelpBookPageData] = []

	for page in pages:
		if page == null:
			continue

		if page.is_unlocked():
			out.append(page)

	return out


func get_page_by_id(page_id: String) -> HelpBookPageData:
	page_id = page_id.strip_edges()
	if page_id == "":
		return null

	for page in pages:
		if page == null:
			continue

		if page.page_id == page_id:
			return page

	return null
