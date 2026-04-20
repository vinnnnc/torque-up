# Placement And Editor

## Placement Overview

Placement is handled by `PlacementController` plus `PlacementRules`.

Current features:

- preview ghost with valid/invalid color
- socket markers and active socket ring
- 8-way drag lock for repeated gear placement
- compound stack placement with explicit rejection feedback for invalid pairings
- specialized chain and shaft placement flows

## Snapping Rules

Standard gears:

- snap using circular mesh-perimeter logic

Shafts:

- use dedicated endpoint snapping and metadata-driven linkage

Flywheel, clutch, differential:

- no longer expose the whole perimeter for snapping
- now expose only discrete port sockets as valid snap origins

This port-based rule applies both to preview markers and actual placement results.

## Chain Placement

Chain placement is currently a two-click workflow:

1. select the first pulley/sprocket
2. select the second pulley/sprocket

Current chain rules:

- span limit is enforced
- chain auto-converts eligible endpoints to sprocket mode
- conversion is blocked with feedback when the endpoint stack has active gear-mesh neighbours
- chain is stored under the chain component type
- older belt terminology remains in compatibility paths only

## Shaft Placement

Shaft placement is a dedicated connector workflow.

Current rules:

- first click anchors the shaft start
- second endpoint can snap to another gear
- shaft nodes store endpoint instance metadata
- shaft hit testing and placement blocking use shaft-specific logic instead of generic gear radius rules

## Port-Limited Components

The graph layer and placement layer both understand port-limited components.

Currently supported:

- clutch: 2 ports
- differential: 3 ports

These ports affect:

- snapping
- connectivity validation
- visual legibility

## Deletion

Delete mode removes the nearest valid component.

Current behavior:

- attached chains are also collected and removed with their connected component
- shaft deletion uses special distance checks against the shaft geometry instead of center-only checks

## Dev Level Editor

The built-in dev editor supports:

- placing power nodes
- placing zones
- placing barriers
- saving a dev level
- loading a dev level
- clearing the current level

Current compatibility behavior:

- save/load supports modern chain naming
- old belt-based data remains load-compatible

## Save Data Notes

Serialized component entries currently preserve:

- component type
- world position
- rotation
- shaft metadata where needed
- stack parent/root relationships
- chain endpoint relationships
