class_name Sm2PracticeDefinition
extends RefCounted
var id: String
var title: String
var seconds: int
var awards: Dictionary[String,int] = {}

func copy() -> Sm2PracticeDefinition:
	var value: Sm2PracticeDefinition = Sm2PracticeDefinition.new()
	value.id=id; value.title=title; value.seconds=seconds
	value.awards=awards.duplicate()
	return value
