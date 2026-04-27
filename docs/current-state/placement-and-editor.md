# Placement And Editor

## Placement Overview

Placement is handled by `PlacementController` plus `PlacementRules`.

Current features:

- preview ghost with valid/invalid color
- socket markers and active socket ring
- 8-way drag lock for repeated gear placement
- compound stack placement with explicit rejection feedback for invalid pairings

## Snapping Rules

Standard gears:

- snap using circular mesh-perimeter logic

## Deletion

Delete mode removes the nearest valid component.

Current behavior:

- removes the nearest gear by center-distance

## Dev Level Editor

The built-in dev editor supports:

- placing power nodes
- placing zones
- placing barriers
- saving a dev level
- loading a dev level
- clearing the current level

## Save Data Notes

Serialized component entries currently preserve:

- component type
- world position
- rotation
- stack parent/root relationships
