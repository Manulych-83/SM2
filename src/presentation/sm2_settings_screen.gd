class_name Sm2SettingsScreen
extends Control
signal closed
const UI: GDScript=preload("res://src/presentation/sm2_camp_screen.gd")
const B: GDScript=preload("res://src/presentation/sm2_bronze_theme.gd")
var preferences: Sm2DisplayPreferences=Sm2DisplayPreferences.new()
var draft: Dictionary={}
var original: Dictionary={}
var mode: OptionButton
var resolution: OptionButton
var vsync: CheckButton
var notice: Label
var countdown: Label
var keep: Button
var undo: Button
var apply_button: Button
var reset: Button
var timer: Timer
var pending: bool=false
var bindings_editor: Sm2ControlsEditor

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme=B.create()
	var loaded: Dictionary=preferences.read(); draft=loaded.value.duplicate()
	var panel: Panel=Panel.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_theme_stylebox_override("panel",B.box(B.BACKGROUND,B.BACKGROUND,0)); add_child(panel)
	var margin: MarginContainer=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); panel.add_child(margin)
	for side: String in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	var page: VBoxContainer=VBoxContainer.new(); page.add_theme_constant_override("separation",16); margin.add_child(page)
	var header: HBoxContainer=HBoxContainer.new(); page.add_child(header)
	var title: Label=UI.label("НАСТРОЙКИ И УПРАВЛЕНИЕ",26,B.GOLD); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	header.add_child(UI.button("Назад","SettingsBack",leave))
	var columns: HBoxContainer=HBoxContainer.new(); columns.size_flags_vertical=Control.SIZE_EXPAND_FILL; columns.add_theme_constant_override("separation",20); page.add_child(columns)
	var left: PanelContainer=UI.frame(columns); left.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var display: VBoxContainer=UI.scroll(left); display.add_theme_constant_override("separation",18)
	display.add_child(UI.label("ИЗОБРАЖЕНИЕ",21,B.GOLD))
	display.add_child(UI.label("Базовый режим — полный экран, композиция 2560 × 1440. Пропорции интерфейса сохраняются при любом выбранном размере.",16,B.MUTED))
	mode=OptionButton.new(); mode.name="SettingsMode"; mode.add_item("Полный экран"); mode.add_item("Окно"); display.add_child(mode)
	mode.item_selected.connect(func(index: int) -> void: draft.mode="fullscreen" if index==0 else "windowed"; synchronize())
	display.add_child(UI.label("Размер окна",17,B.TEXT))
	resolution=OptionButton.new(); resolution.name="SettingsResolution"; display.add_child(resolution)
	for value: String in Sm2DisplayPreferences.RESOLUTIONS: resolution.add_item(value.replace("x"," × "))
	resolution.item_selected.connect(func(index: int) -> void: draft.resolution=Sm2DisplayPreferences.RESOLUTIONS[index])
	display.add_child(UI.label("Полный экран использует размер текущего монитора. Если выбранное окно не помещается, оно уменьшается до доступной рабочей области.",15,B.MUTED))
	vsync=CheckButton.new(); vsync.name="SettingsVsync"; vsync.text="Вертикальная синхронизация"; display.add_child(vsync)
	vsync.toggled.connect(func(enabled: bool) -> void: draft.vsync=enabled)
	display.add_child(UI.label("Синхронизация ограничивает разрывы изображения. На правила и скорость пошагового боя эта настройка не влияет.",15,B.MUTED))
	reset=UI.button("Базовые настройки","SettingsDefaults",func() -> void: draft=Sm2DisplayPreferences.DEFAULT.duplicate(); synchronize()); display.add_child(reset)
	apply_button=UI.button("Применить","SettingsApply",preview); display.add_child(apply_button)
	countdown=UI.label("",17,B.PSI); countdown.name="SettingsCountdown"; display.add_child(countdown)
	keep=UI.button("Оставить и сохранить","SettingsKeep",confirm); display.add_child(keep)
	undo=UI.button("Вернуть прежнее","SettingsRevert",revert); display.add_child(undo)
	var right: PanelContainer=UI.frame(columns); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var controls_page: VBoxContainer=VBoxContainer.new(); right.add_child(controls_page)
	var controls: VBoxContainer=UI.scroll(controls_page)
	var footer: VBoxContainer=VBoxContainer.new(); controls_page.add_child(footer)
	bindings_editor=Sm2ControlsEditor.new(); bindings_editor.name="ControlsEditor"; bindings_editor.footer=footer; controls.add_child(bindings_editor)
	controls.add_child(UI.label("МЫШЬ И НАВИГАЦИЯ",21,B.GOLD))
	var entries: Array=JSON.parse_string(FileAccess.get_file_as_string("res://content/presentation/controls.json"))
	for entry: Dictionary in entries:
		controls.add_child(UI.label(entry.keys,18,B.GOLD)); controls.add_child(UI.label(entry.text,16,B.TEXT))
	controls.add_child(UI.label("Возврат со страницы отменяет несохранённые изменения клавиш. Настройки изображения сохраняются отдельно.",14,B.MUTED))
	notice=UI.label("Изменения сохраняются отдельно от кампаний после подтверждения." if loaded.ok else "Не удалось прочитать настройки. Выбраны базовые значения; кампании не затронуты.",15,B.GOLD); notice.name="SettingsNotice"; page.add_child(notice)
	timer=Timer.new(); timer.name="SettingsTimer"; timer.one_shot=true; timer.wait_time=15; timer.timeout.connect(revert); add_child(timer)
	synchronize()

func synchronize() -> void:
	mode.select(0 if draft.mode=="fullscreen" else 1); resolution.select(Sm2DisplayPreferences.RESOLUTIONS.find(draft.resolution)); vsync.set_pressed_no_signal(draft.vsync)
	mode.disabled=pending; resolution.disabled=pending or draft.mode=="fullscreen"; vsync.disabled=pending; reset.disabled=pending; apply_button.disabled=pending
	keep.visible=pending; undo.visible=pending; countdown.visible=pending

func preview() -> void:
	if pending: return
	if not bindings_editor.capturing.is_empty(): return
	original=Sm2DisplaySettings.capture(get_window()); pending=true
	Sm2DisplaySettings.apply(get_window(),draft); timer.start(); synchronize()
	notice.text="Проверьте изображение. Без подтверждения прежние параметры вернутся автоматически."

func confirm() -> void:
	if not pending: return
	if not preferences.write(draft): revert(); notice.text="Не удалось сохранить настройки. Прежнее изображение восстановлено."; return
	timer.stop(); pending=false; original.clear(); synchronize(); notice.text="Настройки сохранены."

func revert() -> void:
	if not pending: return
	timer.stop(); Sm2DisplaySettings.restore(get_window(),original); pending=false; original.clear(); synchronize(); notice.text="Прежнее изображение восстановлено. Изменения не сохранены."

func leave() -> void:
	revert(); closed.emit()

func _process(_delta: float) -> void:
	if pending: countdown.text="Оставить изображение? Возврат через %s сек." % ceili(timer.time_left)

func _exit_tree() -> void:
	if pending: Sm2DisplaySettings.restore(get_window(),original)

func _unhandled_input(event: InputEvent) -> void:
	if Sm2Controls.back(event):
		get_viewport().set_input_as_handled()
		if pending: revert()
		else: leave()
