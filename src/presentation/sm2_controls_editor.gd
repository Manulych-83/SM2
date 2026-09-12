class_name Sm2ControlsEditor
extends VBoxContainer
const UI: GDScript=preload("res://src/presentation/sm2_camp_screen.gd")
var preferences: Sm2ControlPreferences=Sm2ControlPreferences.new()
var draft: Dictionary={}
var capturing: String=""
var message: Label
var buttons: Dictionary={}
var rows: Array=[]
var footer: VBoxContainer

func _ready() -> void:
	draft=Sm2Controls.bindings.duplicate(); rows=Sm2Controls.definitions()
	add_theme_constant_override("separation",10)
	add_child(UI.label("КЛАВИШИ",21,Sm2BronzeTheme.GOLD))
	add_child(UI.label("Нажмите на клавишу и выберите новую: A–Z, 0–9 или F1–F12 без сочетаний. Обозначения латинские; положение клавиши сохраняется в русской раскладке. Esc отменяет выбор и всегда остаётся клавишей возврата.",15,Sm2BronzeTheme.MUTED))
	for row: Dictionary in rows:
		var line: HBoxContainer=HBoxContainer.new(); add_child(line)
		var title: Label=UI.label(row.title,16,Sm2BronzeTheme.TEXT); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; line.add_child(title)
		var key: Button=UI.button("","Bind_"+row.id,begin.bind(str(row.id))); key.custom_minimum_size.x=110; line.add_child(key); buttons[row.id]=key
	if footer==null: footer=self
	message=UI.label("Выбор клавиш вступит в силу после сохранения." if Sm2Controls.load_ok else "Файл управления повреждён. Используются базовые клавиши; сохраните их или выберите свои.",15,Sm2BronzeTheme.GOLD); message.name="BindingsNotice"; footer.add_child(message)
	footer.add_child(UI.button("Сохранить управление","BindingsSave",save))
	var actions: HBoxContainer=HBoxContainer.new(); footer.add_child(actions)
	actions.add_child(UI.button("Базовые клавиши","BindingsDefaults",func() -> void: capturing=""; draft=Sm2ControlPreferences.DEFAULT.duplicate(); refresh(); message.text="Базовые клавиши подготовлены. Нажмите «Сохранить управление»."))
	actions.add_child(UI.button("Отменить изменения","BindingsDiscard",func() -> void: capturing=""; draft=Sm2Controls.bindings.duplicate(); refresh(); message.text="Несохранённые изменения отменены."))
	for button: Node in actions.get_children(): (button as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	refresh()

func begin(id: String) -> void:
	var settings: Sm2SettingsScreen=get_parent_settings()
	if settings!=null and settings.pending: message.text="Сначала подтвердите или отмените изображение."; return
	capturing=id; refresh(); message.text="Нажмите новую клавишу. Esc — отменить выбор."

func get_parent_settings() -> Sm2SettingsScreen:
	var node: Node=get_parent()
	while node!=null:
		if node is Sm2SettingsScreen: return node as Sm2SettingsScreen
		node=node.get_parent()
	return null

func refresh() -> void:
	for id: String in buttons: buttons[id].text="Нажмите…" if capturing==id else Sm2Controls.label_for(id,draft)

func save() -> void:
	if not capturing.is_empty(): return
	if not preferences.write(draft): message.text="Не удалось сохранить управление. Прежние клавиши продолжают работать."; return
	Sm2Controls.bindings=draft.duplicate(); Sm2Controls.load_ok=true; message.text="Управление сохранено."

func _input(event: InputEvent) -> void:
	if capturing.is_empty() or not event is InputEventKey: return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo: return
	var code: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
	if code==KEY_ESCAPE: capturing=""; refresh(); message.text="Выбор отменён."; return
	if event.ctrl_pressed or event.alt_pressed or event.shift_pressed or event.meta_pressed or not Sm2ControlPreferences.allowed_key(code):
		message.text="Выберите A–Z, 0–9 или F1–F12 без сочетаний. Esc — отмена."; return
	for row: Dictionary in rows:
		if row.id!=capturing and draft[row.id]==code:
			message.text="Клавиша занята: «%s». Выберите другую или сначала измените эту привязку." % row.title; return
	draft[capturing]=code; capturing=""; refresh(); message.text="Клавиша выбрана. Нажмите «Сохранить управление»."
