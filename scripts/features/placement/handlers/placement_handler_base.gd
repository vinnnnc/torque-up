## PlacementHandlerBase
## Abstract base for per-component placement handlers.
##
## Subclass this for each component type. Pass a PlacementHandlerContext to
## init() before activating. Handlers write preview state (socket_markers,
## active_socket_*) directly onto ctx; PlacementController reads them in
## _draw() and for the socket ring overlay.
class_name PlacementHandlerBase
extends RefCounted

const PlacementHandlerContext = preload("res://scripts/features/placement/handlers/placement_handler_context.gd")

## The shared context provided by PlacementController.
var ctx: PlacementHandlerContext = null

## Call immediately after new(). Returns self for chaining.
func init(context: PlacementHandlerContext) -> PlacementHandlerBase:
	ctx = context
	return self

# -- Lifecycle -----------------------------------------------------------------

## Called when this handler's component is selected.
func activate() -> void:
	pass

## Called when another component is selected or placement is cancelled.
func deactivate() -> void:
	pass

# -- Per-frame -----------------------------------------------------------------

## Update preview node position, socket_markers, and active_socket state.
## mouse_pos is in world space. preview_node may be null.
func update_preview(_mouse_pos: Vector2, _preview_node: Node2D) -> void:
	pass

## Draw handler-specific overlays via draw_node (called inside PlacementController._draw()).
func draw_overlay(_draw_node: Node2D) -> void:
	pass

## Called every frame (un-throttled) for drag logic, auto-place timers, etc.
## Separate from update_preview which may be throttled for performance.
func process(_mouse_pos: Vector2) -> void:
	pass

# -- Input ---------------------------------------------------------------------

## Left mouse button pressed (single placement click).
func on_click(_world_pos: Vector2) -> void:
	pass

## Left mouse button held down at the start of a drag.
func on_mouse_down(_world_pos: Vector2) -> void:
	pass

## Left mouse button released at the end of a drag.
func on_mouse_up(_world_pos: Vector2) -> void:
	pass

## Right click or Escape: cancel any in-progress drag/selection.
func cancel() -> void:
	pass

# -- Instance configuration ---------------------------------------------------

## Set component_type meta and visual properties on a freshly instantiated node.
func configure_instance(_instance: Node2D) -> void:
	pass
