extends RefCounted

static func run(t: Sm2TestHarness) -> void:
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/packages/survival.json"))
	var previous: Array=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/catalog_legacy_fingerprints.json"))
	var profile_index: int=0
	for flags: Array in [[false,false],[true,false],[true,true]]:
		var c: Dictionary=Sm2SurvivalContentLoader.load_scenario(flags[0],flags[1])
		t.expect(c.ok,"production package loader "+str(flags))
		if not c.ok: return
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/rules.json"))
		expected.items.append_array(JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/devices.json")))
		if flags[0]:
			expected.version="sm2.survival.content.2"
			expected.devices=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/prostheses.json"))
			expected.items.append({"id":"repair_parts","name":"Комплект деталей","mass":100,"volume":1,"size":1,"capacity":0,"max_mass":0,"max_size":0,"quick":false,"slot":""})
		if flags[1]:
			var layers: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/survival/tissues.json"))
			expected.version="sm2.survival.content.3"; expected.tissue_layers=layers.tissue_layers; expected.supplies=layers.supplies; expected.items.append_array(layers.items)
		t.equal(c.survival.to_data(),expected,"compiled data preserves legacy order and fields")
		t.equal(c.survival.fingerprint(),previous[profile_index].hash,"legacy catalog fingerprint")
		t.equal(c.journey_fingerprint,previous[profile_index].journey,"legacy campaign fingerprint")
		profile_index+=1
		for item: Dictionary in expected.items:
			t.equal(c.survival.item(item.id),item,"indexed item exact "+item.id)
		for part: Dictionary in expected.parts: t.equal(c.survival.part_name(part.id),part.name,"indexed part exact")
		for device: Dictionary in expected.get("devices",{}).get("definitions",[]): t.equal(c.survival.device(device.id),device,"indexed device exact")
		t.equal(c.survival.item("missing"),{},"missing item")
		t.equal(c.survival.device("missing"),{},"missing device")
		t.equal(c.survival.part_name("missing"),"missing","missing part")
		var detached: Dictionary=c.survival.item("bandage"); detached.mass=-1
		t.equal(c.survival.item("bandage").mass,50,"public lookup detached")
		var changed: Dictionary=expected.duplicate(true); changed.items[0].mass=51
		t.expect(c.survival.build(changed).is_empty(),"rebuild supported")
		t.equal(c.survival.item("bandage").mass,51,"rebuild replaces index")
		t.equal(c.survival.fingerprint(),Sm2Canonical.hash(changed),"rebuild invalidates fingerprint")
		changed.items.append(changed.items[0].duplicate(true))
		t.expect(not c.survival.build(changed).is_empty(),"duplicate rejects rebuild")
		t.equal(c.survival.item("bandage").mass,51,"failed rebuild preserves index")
		var snapshot: Dictionary=c.survival.to_data(); snapshot.items[0].mass=-9
		t.equal(c.survival.item("bandage").mass,51,"public catalog detached")
	var resolved: Dictionary=Sm2ContentPackages.resolve(manifest,["survival.tissues"])
	t.expect(resolved.ok,"package dependencies resolve")
	t.equal(resolved.packages.map(func(p: Dictionary) -> String: return p.id),["survival.base","survival.devices","survival.repair","survival.tissues"],"dependency order")
	for defect: String in ["duplicate","missing","cycle","source_type","path","extra","root","empty","requires_type","duplicate_dependency"]:
		var bad: Dictionary=manifest.duplicate(true); var roots: Array[String]=["survival.tissues"]
		match defect:
			"duplicate": bad.packages.append(bad.packages[0].duplicate(true))
			"missing": bad.packages[0].requires=["unknown"]
			"cycle": bad.packages[0].requires=["survival.tissues"]
			"source_type": bad.packages[0].sources=[1]
			"path": bad.packages[0].sources[0].path="res://content/../project.godot.json"
			"extra": bad.extra=1
			"root": roots=["missing"]
			"empty": roots=[]
			"requires_type": bad.packages[0].requires=[1]
			"duplicate_dependency": bad.packages[1].requires=["survival.base","survival.base"]
		t.expect(not Sm2ContentPackages.resolve(bad,roots).ok,"invalid manifest: "+defect)
	for path: String in ["res://.local/test.json","user://test.json","res://content//test.json","res://content/./test.json","res://content/a\\b.json"]:
		t.expect(not Sm2ContentPackages.load_groups(path,["root"]).ok,"restricted authoring path: "+path)
	t.expect(not Sm2ContentPackages.load_groups("res://content/no-such-package.json",["root"]).ok,"missing file diagnostic")
	_compile(t)
	_scale(t)
	t.complete_suite("content_packages")

static func _compile(t: Sm2TestHarness) -> void:
	var source: Dictionary={"group":"items","path":"res://content/a.json","field":"items"}
	var manifest: Dictionary={"format":Sm2ContentPackages.VERSION,"packages":[{"id":"a","requires":[],"sources":[source]},{"id":"b","requires":["a"],"sources":[{"group":"items","path":"res://content/b.json","field":""}]}]}
	var docs: Dictionary={"res://content/a.json":{"items":[{"id":"one","value":1}]},"res://content/b.json":[{"id":"two","value":2}]}
	var compiled: Dictionary=Sm2ContentPackages.compile(manifest,["b"],docs)
	t.expect(compiled.ok,"data-only extension loads")
	t.equal(compiled.groups.items,[{"id":"one","value":1},{"id":"two","value":2}],"base plus extension")
	t.equal(compiled.origins.items.two.package,"b","source provenance")
	compiled.groups.items[0].value=99
	t.equal(docs["res://content/a.json"].items[0].value,1,"compilation detached")
	var reversed: Dictionary=manifest.duplicate(true); reversed.packages.reverse()
	t.equal(Sm2ContentPackages.compile(reversed,["b"],docs).groups,Sm2ContentPackages.compile(manifest,["b"],docs).groups,"dependencies order independent of manifest order")
	var dormant: Dictionary=manifest.duplicate(true)
	dormant.packages.append({"id":"inactive","requires":[],"sources":[{"group":"items","path":"res://content/unread.json","field":""}]})
	t.expect(Sm2ContentPackages.compile(dormant,["b"],docs).ok,"unselected source not required")
	var typed: Dictionary=manifest.duplicate(true); typed.packages[0].sources[0].integer_fields=["value"]
	for number: Variant in [2.0,2.5,true,"2",null,INF]:
		var typed_docs: Dictionary=docs.duplicate(true); typed_docs["res://content/a.json"].items[0].value=number
		var result: Dictionary=Sm2ContentPackages.compile(typed,["b"],typed_docs)
		t.equal(result.ok,typeof(number)==TYPE_FLOAT and number==2.0,"integer field validation: "+str(number))
		if result.ok: t.equal(typeof(result.groups.items[0].value),TYPE_INT,"declared integer remains integer in memory")
	for defect: String in ["missing","field","array","row","identity","duplicate"]:
		var bad: Dictionary=docs.duplicate(true)
		match defect:
			"missing": bad.erase("res://content/a.json")
			"field": bad["res://content/a.json"]={}
			"array": bad["res://content/a.json"].items={}
			"row": bad["res://content/b.json"]=[false]
			"identity": bad["res://content/b.json"]=[{"id":[]}]
			"duplicate": bad["res://content/b.json"]=[{"id":"one"}]
		var failed: Dictionary=Sm2ContentPackages.compile(manifest,["b"],bad)
		t.expect(not failed.ok,"invalid document: "+defect)
		if defect=="duplicate": t.equal(failed.errors[0].previous.package,"a","duplicate identifies both sources")

static func _scale(t: Sm2TestHarness) -> void:
	var raw: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true).survival.to_data()
	var template: Dictionary=raw.items[0].duplicate(true)
	while raw.items.size()<10000:
		var item: Dictionary=template.duplicate(true); item.id="scale:item."+str(raw.items.size()); raw.items.append(item)
	var manifest: Dictionary={"format":Sm2ContentPackages.VERSION,"packages":[{"id":"large","requires":[],"sources":[{"group":"items","path":"res://content/large.json","field":"items"}]}]}
	var docs: Dictionary={"res://content/large.json":raw}
	var begin: int=Time.get_ticks_usec()
	var compiled: Dictionary=Sm2ContentPackages.compile(manifest,["large"],docs)
	t.expect(compiled.ok,"10000 distinct definitions compile")
	var cat: Sm2SurvivalCatalog=Sm2SurvivalCatalog.new()
	t.expect(cat.build(raw).is_empty(),"10000 physical definitions validate")
	var built: int=Time.get_ticks_usec()
	var mismatch: int=0
	for entry: Dictionary in raw.items:
		if cat.item(entry.id)!=entry: mismatch+=1
	t.equal(mismatch,0,"all 10000 indexed definitions equal source")
	var looked_up: int=Time.get_ticks_usec()
	var inventory: Sm2PhysicalInventory=Sm2PhysicalInventory.new()
	for index: int in raw.items.size(): inventory.add(index+1,raw.items[index].id,"ground","camp")
	t.equal(inventory.validate(cat,[],["camp"]),"","10000 instances of different types validate together")
	var restored: Dictionary=Sm2PhysicalInventory.decode(inventory.to_data(),cat,[],["camp"])
	t.expect(restored.ok,"10000 different item instances roundtrip")
	if restored.ok: t.equal(restored.inventory.to_data(),inventory.to_data(),"physical inventory exact")
	var damaged: Dictionary=raw.duplicate(true); damaged.supplies.care[damaged.supplies.care.keys()[0]]="missing"
	t.expect(not cat.build(damaged).is_empty(),"missing supply reference still rejects")
	var extra: Dictionary=template.duplicate(true); extra.id="overflow"; raw.items.append(extra)
	t.expect(not cat.build(raw).is_empty(),"10001 definitions rejected")
	t.expect(not Sm2ContentPackages.compile(manifest,["large"],docs).ok,"10001 package rows rejected")
	t.equal(cat.item("scale:item.9999").id,"scale:item.9999","failed overflow preserves previous catalog")
	print("CATALOG_SCALE definitions=10000 compile_build_ms=",float(built-begin)/1000.0," lookup_all_ms=",float(looked_up-built)/1000.0)
