class_name Sm2PsionicCostQuery
extends RefCounted
## One derived price for camp descriptions, projected queries and real casts.
static func resolve(base: int,catalog: Sm2BodyUpgradeCatalog=null,body: Sm2BodyUpgradeState=null) -> Dictionary:
	var sources: Array[Dictionary]=[]
	if catalog!=null: sources=catalog.focus_modifiers(body)
	var bonus: int=0
	for source: Dictionary in sources: bonus+=int(source.amount)
	return {"base":base,"bonus":bonus,"total":base+bonus,"sources":sources}
