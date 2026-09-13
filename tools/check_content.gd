extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	if args.size() not in [2,4] or args[0]!="--report" or (args.size()==4 and args[2] not in ["--progression","--items","--progress-packages"]):
		push_error("Expected --report path [--progression path | --items res://content/manifest.json]"); quit(2); return
	var report: Dictionary={"format":"sm2.content.audit.1","ok":false,"errors":[],"source":"production_campaign"}
	if args.size()==4 and args[2]=="--progression":
		report.source=args[3]
		var file: FileAccess=FileAccess.open(args[3],FileAccess.READ)
		if file==null: report.errors.append("file_unreadable")
		elif file.get_length()>8*1024*1024: report.errors.append("author_file_exceeds_8_mib")
		else:
			var parser: JSON=JSON.new()
			if parser.parse(file.get_as_text())!=OK: report.errors.append("JSON line %s: %s" % [parser.get_error_line(),parser.get_error_message()])
			elif not parser.data is Dictionary: report.errors.append("root_must_be_object")
			else:
				report.progression=Sm2ProgressContentAudit.inspect(parser.data)
				report.ok=report.progression.ok
	elif args.size()==4 and args[2]=="--progress-packages":
		report.source=args[3]
		var content: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true)
		if not content.ok: report.errors=Array(content.errors)
		else:
			var expanded: Dictionary=Sm2ProgressPackageLoader.load_extensions(content.development._shared_progression().to_data(),args[3])
			if not expanded.ok: report.errors=Array(expanded.errors)
			else:
				var development: Sm2DevelopmentCatalog=Sm2DevelopmentCatalog.new()
				var errors: PackedStringArray=development.build(content.development.to_data(),expanded.catalog,content.combat,true)
				report.progression=Sm2ProgressContentAudit.inspect(expanded.raw); report.origins=expanded.origins
				report.errors=Array(errors); report.ok=errors.is_empty() and report.progression.ok
	else:
		var manifest: String=args[3] if args.size()==4 else "res://content/packages/survival.json"
		report.source=manifest
		var content: Dictionary=Sm2SurvivalContentLoader.load_scenario(true,true,manifest)
		if not content.ok: report.errors=Array(content.get("errors",[]))
		else:
			var packages: Dictionary=Sm2ContentPackages.load_groups(manifest,["survival.tissues"])
			report.items={"definitions":content.survival.to_data().items.size(),"packages":packages.packages,"origins":packages.origins}
			var session: Sm2JourneySession=Sm2JourneySession.new(content,Sm2AiContentLoader.load_profile().profile,null)
			session.world.start("content:audit")
			report.progression=Sm2ProgressContentAudit.inspect(content.development.progression().to_data())
			report.expedition=Sm2ExpeditionBrief.load_for(session.journey())
			report.journey_fingerprint=content.journey_fingerprint
			report.ok=report.progression.ok and not report.expedition.is_empty()
	var output: FileAccess=FileAccess.open(args[1],FileAccess.WRITE)
	if output==null: push_error("Cannot write report"); quit(2); return
	output.store_string(JSON.stringify(report,"\t")); output.close()
	print("CONTENT_OK" if report.ok else "CONTENT_INVALID")
	quit(0 if report.ok else 1)
