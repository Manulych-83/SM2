class_name Sm2PracticeDefinition
extends RefCounted
var id: String
var title: String
var seconds: int
var required_track: String = ""
var required_value: int = 0
var assistance: int = 0
var assistance_name: String = ""
var awards: Dictionary[String,int] = {}

func copy() -> Sm2PracticeDefinition:
	var value: Sm2PracticeDefinition = Sm2PracticeDefinition.new()
	value.id=id; value.title=title; value.seconds=seconds
	value.awards=awards.duplicate()
	value.required_track=required_track; value.required_value=required_value
	value.assistance=assistance; value.assistance_name=assistance_name
	return value
