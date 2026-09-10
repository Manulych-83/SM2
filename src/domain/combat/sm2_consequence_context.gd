class_name Sm2ConsequenceContext
extends RefCounted
## Exists only inside one detached command transaction.
var checked: Dictionary[int, bool] = {}
var facts: Array[Dictionary] = []
