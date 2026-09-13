extends RefCounted
const FIXTURE=preload("res://tests/fixtures/sm2_scale_fixture.gd")

static func run(t: Sm2TestHarness) -> void:
	var ids: Array[String]=["a","b","c","d","e"]
	var dependencies: Dictionary={"a":["c"],"b":["c"],"c":[],"d":["a","b"],"e":[]}
	var graph: Dictionary=Sm2DependencyGraph.inspect(ids,dependencies)
	t.expect(graph.ok,"branching graph accepted")
	var positions: Dictionary={}
	for index: int in graph.order.size(): positions[graph.order[index]]=index
	for id: String in dependencies:
		for required: String in dependencies[id]: t.expect(positions[required]<positions[id],"every prerequisite precedes dependent")
	t.equal(graph,Sm2DependencyGraph.inspect(ids,dependencies),"graph deterministic")
	t.equal(ids,["a","b","c","d","e"],"input IDs unchanged")
	var bad: Dictionary=dependencies.duplicate(true); bad.c=["d"]
	graph=Sm2DependencyGraph.inspect(ids,bad)
	t.expect(not graph.ok and graph.blocked==["a","b","c","d"],"cycle and dependents identified without unrelated vertex")
	bad=dependencies.duplicate(true); bad.a=["missing"]
	graph=Sm2DependencyGraph.inspect(ids,bad)
	t.expect(not graph.ok and graph.errors[0].requires=="missing","missing reference has source and target")
	var duplicate: Array[String]=["a","a"]
	t.expect(not Sm2DependencyGraph.inspect(duplicate,{}).ok,"duplicate graph ID rejected")
	for count: int in [1000,10000]:
		var large: Dictionary=FIXTURE.graph(count)
		graph=Sm2DependencyGraph.inspect(large.ids,large.dependencies)
		t.expect(graph.ok and graph.order.size()==count,"large graph accepted")
		t.equal(graph.order[0],large.ids[-1],"reverse chain order start")
		t.equal(graph.order[-1],large.ids[0],"reverse chain order end")
	var raw: Dictionary=FIXTURE.catalog(1000)
	var catalog: Sm2ProgressCatalog=Sm2ProgressCatalog.new()
	t.expect(catalog.build(raw).is_empty(),"1000 node production parser")
	var original: Dictionary=catalog.to_data(); var fingerprint: String=catalog.fingerprint()
	t.equal(fingerprint,Sm2Canonical.hash(original),"fingerprint algorithm unchanged")
	raw.nodes[0].name="Mutated input"; var detached: Dictionary=catalog.to_data(); detached.nodes.clear()
	t.equal(catalog.fingerprint(),fingerprint,"detached source and output cannot invalidate fingerprint")
	var node: Sm2ProgressNodeDefinition=catalog.node("scale:node.00000"); node.requires.clear()
	t.equal(catalog.node(node.id).requires.size(),1,"node returned detached")
	bad=original.duplicate(true); bad.nodes[-1].requires=[bad.nodes[0].id]
	t.equal(catalog.build(bad),PackedStringArray(["progress_node_cycle"]),"legacy cycle code preserved")
	t.equal(catalog.fingerprint(),fingerprint,"failed rebuild keeps prior hash")
	t.equal(catalog.to_data(),original,"failed rebuild keeps prior catalog")
	var audit: Dictionary=Sm2ProgressContentAudit.inspect(bad)
	t.expect(not audit.ok and audit.diagnostics[0].code=="cycle_or_dependent","author sees blocked graph")
	bad=original.duplicate(true); bad.nodes[0].requires=["missing"]
	audit=Sm2ProgressContentAudit.inspect(bad)
	t.expect(not audit.ok and audit.diagnostics[0].path=="nodes[0].requires" and audit.diagnostics[0].requires=="missing","author sees exact bad reference path")
	bad=original.duplicate(true); bad.nodes[1].id=bad.nodes[0].id
	audit=Sm2ProgressContentAudit.inspect(bad)
	t.expect(not audit.ok and audit.diagnostics[0].path=="nodes[1].id" and audit.diagnostics[0].first=="nodes[0].id","author sees both duplicate locations")
	bad=original.duplicate(true); bad.nodes[0].min_level="wrong"
	t.expect(not Sm2ProgressContentAudit.inspect(bad).ok,"valid graph cannot bypass schema validation")
	t.expect(not Sm2ProgressContentAudit.inspect({"nodes":[null,{"id":7}]}).ok,"malformed author data does not crash diagnostic")
	t.equal(catalog.build(FIXTURE.catalog(1001)),PackedStringArray(["progress_content_group"]),"historical limit preserved")
	t.equal(catalog.fingerprint(),fingerprint,"size refusal atomic")
	var changed: Dictionary=original.duplicate(true); changed.nodes[0].name="Revised"
	t.expect(catalog.build(changed).is_empty(),"valid rebuild accepted")
	t.expect(catalog.fingerprint()!=fingerprint and catalog.fingerprint()==Sm2Canonical.hash(changed),"valid rebuild refreshes fingerprint")
	var body: Sm2ProgressBodyState=Sm2ProgressRules.empty_body(2,catalog)
	body.tracks["scale:skill"].earned=1000
	for index: int in range(999,-1,-1):
		var definition: Sm2ProgressNodeDefinition=catalog.node("scale:node.%05d" % index)
		t.equal(Sm2ProgressRules.purchase_error(body,catalog,definition.id),"","real progression prerequisites on large catalog")
		Sm2ProgressRules.purchase(body,definition)
	t.equal(body.tracks["scale:skill"].spent,1000,"real node purchases charge each practice cost")
	t.equal(body.tracks["scale:skill"].earned,1000,"purchases preserve earned level")
	var restored: Dictionary=Sm2ProgressRules.decode_body(body.to_data(),catalog)
	t.expect(restored.ok,"body with 1000 purchased nodes decodes")
	if restored.ok: t.equal(restored.body.to_data(),body.to_data(),"large learned body round trip")
	t.complete_suite("foundation")
