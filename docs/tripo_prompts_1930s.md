# Tripo prompts — 1930s vintage passenger car

Palette shared by every asset:

| Material | Hex |
|---|---|
| Moss green velvet (upholstery) | `#5B6B3A` |
| Varnished dark walnut (wood) | `#6A3A22` |
| Polished brass (fittings) | `#C9A24A` |
| Dark cast iron (legs, frames) | `#2A2826` |
| Exterior bottle green / cream stripe | `#2B4A40` / `#E6D9B8` |
| White porcelain | `#F2F0EA` |

## How these prompts are written

- Each prompt is a 3D model reference for Tripo: one single isolated object on a plain white background, with no environment and no interior around it.
- Tripo has no negative-prompt field, so the prompts describe what IS there (the object alone, empty white space around it, clear glass showing only the white background) instead of long "no ..." lists. Naming an unwanted thing can pull it into the result, so each prompt keeps only a short KEEP OUT line for things Tripo tends to invent.
- If something unwanted still appears, regenerate first. If it keeps appearing, tell Claude which word to rephrase.

## Tripo settings

- PBR textures on, texture resolution 2K.
- Face limit per item is listed in triangles. In quad mode, use half.
- Generate 2–4 variants, rotate each in the viewer, send only a clean one.
- Send to Godot with an empty scene open (not the car scene).

## Checklist (in order)

| # | Asset | Normalize preset | Max triangles | Per car |
|---|---|---|---|---|
| 1 | Double seat | Seat (double) | 14,000 | 20 |
| 2 | Bay table | Bay table | 4,000 | 10 |
| 3 | Luggage rack | Luggage rack | 4,000 | 10 |
| 4 | Ceiling lamp | Ceiling lamp | 3,000 | 8 |
| 5 | Saloon door | Saloon door | 6,000 | 2 |
| 6 | Gangway door | Gangway door | 6,000 | 2 |
| 7 | Exterior door | Side door | 6,000 | 2 |
| 8 | Toilet door | Toilet door | 4,000 | 1 |
| 9 | Toilet | Toilet bowl | 6,000 | 1 |
| 10 | Sink | Sink | 5,000 | 1 |
| 11 | Bogie | Bogie | 15,000 | 2 |

---

## 1. Double seat

```
3D model reference for Tripo: one single isolated 1930s vintage railway double seat for two passengers, shown alone on a plain white background. Moss green velvet upholstery with vertical channel tufting, varnished dark walnut armrests, polished brass trim, dark cast iron side panels and legs, and a fixed center armrest between the two places.

ISOLATED OBJECT: the image contains only this one seat, complete, centered and fully visible, on a seamless plain white studio background. All the space around the seat is empty white. The seat stands on its own; it is not inside a carriage, compartment, room or any interior.

ORIENTATION: upright on its legs, front view. The front of the seat (the side a seated passenger faces) faces the camera. Symmetric left to right. Slightly wider than it is tall.

DIMENSIONS: 110 cm wide, 105 cm tall, 65 cm deep. Cushion tops 44 cm, armrest tops 62 cm and backrest top 105 cm above the bottom of the legs.

PARTS:
1. Exactly two separate seat cushions side by side, each 43 cm wide, 48 cm deep and 12 cm thick, with a rounded front edge and piped seams.
2. Exactly two separate backrests, one behind each cushion, reclined about 10 degrees, 60 cm tall above the cushion, each with five vertical channel-tufted stripes and a rounded top edge.
3. Exactly three fixed armrests at equal height: one at the left end, one at the right end and one in the center. Each is a solid walnut top, 8 cm wide, with rounded ends. The center armrest is fixed in place and clearly separates the two seating places.
4. Two curved cast iron side panels, shaped like a smooth letter C in side view, under the two outer armrests, each outlined with a thin brass edge trim and four round brass rivets. A narrow cast iron post supports the center armrest.
5. The back of both backrests is one smooth walnut panel with a thin brass edge trim.
6. Base: a cast iron frame on exactly two pedestal legs, one under each end, each ending in a flat rectangular foot plate with four brass bolt heads. Open space under the seat between the legs.

MATERIALS:
- Upholstery: moss green (#5B6B3A) cotton velvet with a soft sheen and visible fabric nap, darker shading in the tufting grooves.
- Armrests and back panel: varnished dark walnut (#6A3A22), straight grain, satin gloss.
- Side panels, post, frame and legs: dark cast iron (#2A2826), matte.
- Trim, rivets and bolt heads: polished brass (#C9A24A), warm metallic, faint patina.
- Gentle, even wear: slightly worn velvet on the cushion front edges and armrest ends. Clean overall.

STYLE: realistic 1930s European railway carriage furniture with an Art Deco influence, solid and well crafted.

KEEP OUT: text, numbers and logos anywhere on the object.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures and clear material separation between velvet, wood, cast iron and brass. Every part is connected to the object.
```

## 2. Bay table

```
3D model reference for Tripo: one single isolated 1930s vintage railway wall-mounted table with one leg, shown alone on a plain white background. Varnished dark walnut tabletop with a polished brass edge trim, one dark cast iron column leg on a round base, and a flat brass wall-mounting rail under the back edge.

ISOLATED OBJECT: the image contains only this one table, complete, centered and fully visible, on a seamless plain white studio background. All the space around the table is empty white. The tabletop surface is bare and empty. The table stands on its own; it is not inside a carriage, compartment, room or any interior, and no wall is shown behind it.

ORIENTATION: upright, tabletop perfectly horizontal, front view. The free front edge of the table faces the camera; the back edge (with the mounting rail) is away from the camera. Symmetric left to right.

DIMENSIONS: tabletop 50 cm wide (left to right), 55 cm deep (front to back), 3 cm thick. The tabletop upper surface is 68 cm above the bottom of the base, and it is the highest point of the object: overall height exactly 68 cm.

PARTS:
1. Tabletop: one flat rectangular walnut slab. The two front corners are rounded with a 6 cm radius; the two back corners are square.
2. Edge trim: a thin polished brass band, 3 cm tall, along the front edge and both side edges, flush with the top surface, with small brass rivets every 12 cm.
3. Mounting rail: one flat polished brass rail, 45 cm long, 6 cm tall and 1 cm thick, standing vertically directly under the rear edge of the tabletop, with two round screw heads.
4. Leg: exactly one vertical dark cast iron column, 5 cm in diameter, with a decorative turned ring near the top and near the bottom, placed 12 cm behind the front edge and centered left to right. A small cast iron bracket joins it to the underside of the tabletop.
5. Base: one round dark cast iron disc, 18 cm in diameter and 2 cm thick, with four small brass bolt heads.

MATERIALS:
- Tabletop: varnished dark walnut (#6A3A22), clearly visible straight grain running left to right, satin gloss.
- Trim, rivets, rail and bolt heads: polished brass (#C9A24A), faint patina.
- Leg, bracket and base: dark cast iron (#2A2826), matte.
- Very light scratches on the wood. Clean overall.

STYLE: realistic 1930s European railway carriage furniture, elegant and solid.

KEEP OUT: text, logos and emblems anywhere on the object.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 3. Luggage rack

```
3D model reference for Tripo: one single isolated 1930s vintage railway overhead luggage rack, shown alone on a plain white background. A long, narrow horizontal shelf with a polished brass tubular frame, a dark brown woven cord net stretched inside it, a raised brass front rail, and two ornate cast brass wall brackets at the back.

ISOLATED OBJECT: the image contains only this one luggage rack, complete, centered and fully visible, on a seamless plain white studio background. All the space around the rack is empty white. The rack is empty. It is shown on its own; it is not inside a carriage, compartment, room or any interior, and no wall or ceiling is shown behind it.

ORIENTATION: shelf horizontal, front view from slightly above. The open front edge faces the camera; the back side with the brackets is away from the camera. The long axis runs left to right. Symmetric left to right.

DIMENSIONS: 180 cm long (left to right), 40 cm deep (front to back), 25 cm tall including the brackets. Long and thin: the length is 4.5 times the depth.

PARTS:
1. Frame: one flat rectangular frame of polished brass round tube, 2.5 cm in diameter, 180 x 40 cm, lying horizontally.
2. Net: a woven diamond-mesh net of dark brown cord stretched tightly and flat inside the frame, filling it completely, with openings about 4 cm wide.
3. Front rail: one brass round tube along the front edge, 7 cm above the frame, held by exactly five short vertical brass posts, evenly spaced.
4. Brackets: exactly two cast brass brackets at the back, each 30 cm in from one end. Each is a right-angle shape with a gentle scroll curve: a vertical back plate 25 cm tall with two screw heads, a horizontal arm under the frame, and a curved diagonal brace.

MATERIALS:
- Frame, rail, posts and brackets: polished brass (#C9A24A), warm metallic, faint darker patina in the recesses.
- Net: dark brown twisted cord (#3B2A1E), matte.
- Clean overall.

STYLE: realistic 1930s European railway fittings, elegant.

KEEP OUT: text and logos anywhere on the object.

TECHNICAL: one clean mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 4. Ceiling lamp

```
3D model reference for Tripo: one single isolated 1930s Art Deco railway ceiling lamp, shown alone on a plain white background. A round frosted opal glass dome held by a stepped polished brass ring, mounted on a flat round brass ceiling plate, with a small brass knob at the bottom of the dome.

ISOLATED OBJECT: the image contains only this one lamp, complete, centered and fully visible, on a seamless plain white studio background. All the space around the lamp is empty white. The lamp is shown on its own; it is not attached to a ceiling and not inside a carriage, room or any interior.

GLASS: the dome is plain, even, milky opal white, softly glowing. It is uniform all over; nothing is visible inside it.

ORIENTATION: the flat mounting plate is on top and the glass dome faces down, seen from the side and slightly below. Rotationally symmetric around the vertical axis.

DIMENSIONS: 35 cm in diameter, 18 cm tall overall. Wide and shallow.

PARTS:
1. Ceiling plate: one flat round polished brass plate, 35 cm in diameter and 1.5 cm thick, completely flat on top, with four small screw heads near the edge.
2. Fitting ring: one polished brass ring, 30 cm in diameter and 4 cm tall, directly under the plate, with a stepped Art Deco profile of three concentric bands.
3. Glass dome: one smooth frosted opal glass half-dome, 28 cm in diameter and 12 cm tall, held in the ring, slightly flattened at the bottom.
4. Finial: one small polished brass knob, 3 cm in diameter, at the lowest center point of the dome.

MATERIALS:
- Plate, ring and finial: polished brass (#C9A24A), faint patina.
- Dome: milky opal white glass (#F4EEDC), translucent, evenly bright, very slight warm tint.
- Clean.

STYLE: realistic 1930s Art Deco railway lighting, flush-mounted, simple and elegant.

KEEP OUT: text and logos anywhere on the object.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 5. Saloon door (sliding)

```
3D model reference for Tripo: one single isolated 1930s vintage railway sliding door leaf, shown alone on a plain white background. A varnished dark walnut door with one large clear bevelled glass window in the upper part, a raised walnut panel in the lower part, a polished brass kick plate and a vertical brass bar handle.

ISOLATED OBJECT: the image contains only this one door leaf, complete, centered and fully visible, on a seamless plain white studio background. All the space around the door is empty white. Door leaf only: the edges of the leaf are the outer edges of the object. It is shown on its own; it is not set in a wall or frame and not inside a carriage, corridor, room or any interior.

GLASS: the window is perfectly clear and empty. Through the glass you see only the same plain white background.

ORIENTATION: standing upright on its bottom edge, front view, flat face toward the camera. Both faces look the same. Square outer corners.

DIMENSIONS: 70 cm wide, 200 cm tall, 4 cm thick. A tall narrow rectangle: the height is about 2.9 times the width.

PARTS:
1. Frame: walnut stiles and top rail 8 cm wide, bottom rail 12 cm tall, and one horizontal middle rail 8 cm tall from 72 cm to 80 cm above the bottom.
2. Glass: exactly one clear pane from 80 cm to 188 cm above the bottom, filling the width inside the frame, with a 1 cm bevelled edge and a thin brass glazing bead.
3. Lower panel: exactly one raised rectangular walnut panel between the bottom rail and the middle rail, with a bevelled border.
4. Kick plate: one polished brass plate across the full width at the bottom, 15 cm tall.
5. Handle: exactly one vertical polished brass bar handle, 35 cm long, near the right edge, centered 105 cm above the bottom, standing 4 cm off the surface, on both faces.

MATERIALS:
- Wood: varnished dark walnut (#6A3A22), vertical grain, satin gloss.
- Glass: clear, colorless, slightly reflective.
- Brass: polished brass (#C9A24A), faint patina, slightly worn on the handle.
- Light wear. Clean overall.

STYLE: realistic 1930s European railway carriage joinery, elegant.

KEEP OUT: text, numbers, signs and logos anywhere on the object, including the glass.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 6. Gangway door

```
3D model reference for Tripo: one single isolated 1930s vintage railway end door leaf (the sliding door between two carriages), shown alone on a plain white background. A sturdy varnished dark walnut door with two raised lower panels, one small clear window at eye level with rounded corners in a brass frame, a polished brass kick plate and a recessed brass finger-pull.

ISOLATED OBJECT: the image contains only this one door leaf, complete, centered and fully visible, on a seamless plain white studio background. All the space around the door is empty white. Door leaf only: the edges of the leaf are the outer edges of the object. It is shown on its own; it is not set in a wall or frame and not inside a carriage, corridor, room or any interior.

GLASS: the window is perfectly clear and empty. Through the glass you see only the same plain white background.

ORIENTATION: standing upright on its bottom edge, front view, flat face toward the camera. Both faces look the same. Square outer corners.

DIMENSIONS: 90 cm wide, 200 cm tall, 5 cm thick. A tall rectangle: the height is about 2.2 times the width.

PARTS:
1. Frame: walnut stiles and rails, 10 cm wide on all sides.
2. Window: exactly one clear window, 40 cm wide and 50 cm tall, centered left to right, its bottom edge 125 cm above the bottom of the door, corners rounded with an 8 cm radius, in a polished brass frame 2 cm wide. The walnut around the window is flat.
3. Lower panels: exactly two raised rectangular walnut panels side by side, from 25 cm to 110 cm above the bottom, each with a bevelled border.
4. Kick plate: one polished brass plate across the full width, from the bottom edge up to 25 cm, with six small round screw heads in a row.
5. Finger-pull: exactly one recessed brass finger-pull, 18 cm tall and 5 cm wide, near the right edge, centered 105 cm above the bottom, on both faces.

MATERIALS:
- Wood: varnished dark walnut (#6A3A22), vertical grain, satin gloss.
- Glass: clear, colorless, slightly reflective.
- Brass: polished brass (#C9A24A), faint patina, light scuffs on the kick plate.
- Clean overall.

STYLE: realistic, robust 1930s European railway carriage joinery.

KEEP OUT: text, numbers, signs and logos anywhere on the object, including the glass.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 7. Exterior door (hinged)

```
3D model reference for Tripo: one single isolated 1930s vintage railway carriage exterior door leaf (a hinged passenger entrance door), shown alone on a plain white background. A painted wooden panelled door in dark bottle green with one horizontal cream stripe, a drop-down window in the upper part with a walnut frame, a brass lever handle on the right and three brass hinges on the left edge.

ISOLATED OBJECT: the image contains only this one door leaf, complete, centered and fully visible, on a seamless plain white studio background. All the space around the door is empty white. Door leaf only: the edges of the leaf are the outer edges of the object. It is shown on its own; it is not set in a carriage body, wall or frame, and not inside any interior.

GLASS: the window is perfectly clear and empty. Through the glass you see only the same plain white background.

ORIENTATION: standing upright on its bottom edge, front view. The outside face (painted green) faces the camera; the inside face points away. Flat panel, square corners.

DIMENSIONS: 80 cm wide, 200 cm tall, 6 cm thick. A tall rectangle: the height is 2.5 times the width.

PARTS:
1. Leaf: one flat panelled door. Below the window, exactly two shallow raised rectangular panels, one above the other, outlined by thin beading.
2. Window: exactly one rectangular drop-down window, 56 cm wide and 70 cm tall, centered left to right, from 115 cm to 185 cm above the bottom, clear glass in a varnished walnut frame with slightly rounded corners.
3. Stripe: exactly one cream horizontal stripe across the full width of the outside face, 14 cm tall, its center 60 cm above the bottom.
4. Handle: exactly one polished brass lever handle on the outside face, near the right edge, 105 cm above the bottom.
5. Hinges: exactly three polished brass hinges on the left edge, at 25 cm, 100 cm and 175 cm above the bottom.
6. Inside face: varnished walnut with one small brass pull handle near the right edge.

MATERIALS:
- Outside face: dark bottle green (#2B4A40) glossy coach paint over wood, faint dust near the bottom edge, tiny paint chips at the corners.
- Stripe: cream (#E6D9B8) paint, same gloss.
- Window frame and inside face: varnished dark walnut (#6A3A22).
- Glass: clear, colorless, slightly reflective.
- Brass: polished brass (#C9A24A), faint patina.

STYLE: realistic 1930s European railway carriage door.

KEEP OUT: text, numbers, class numbers, crests and logos anywhere on the object.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 8. Toilet door (hinged)

```
3D model reference for Tripo: one single isolated 1930s vintage railway lavatory door leaf (a hinged door), shown alone on a plain white background. A varnished dark walnut panelled door with one small frosted glass window near the top, a brass ventilation grille near the bottom, a brass lever handle on the right with a small round red lock indicator above it, and three brass hinges on the left edge.

ISOLATED OBJECT: the image contains only this one door leaf, complete, centered and fully visible, on a seamless plain white studio background. All the space around the door is empty white. Door leaf only: the edges of the leaf are the outer edges of the object. It is shown on its own; it is not set in a wall or frame and not inside a carriage, corridor, room or any interior.

GLASS: the frosted window is plain, even, milky translucent white, uniform all over. Nothing is visible behind it.

ORIENTATION: standing upright on its bottom edge, front view, flat face toward the camera. Both faces look the same. Square corners.

DIMENSIONS: 70 cm wide, 200 cm tall, 4 cm thick. A tall narrow rectangle: the height is about 2.9 times the width.

PARTS:
1. Leaf: walnut stiles and rails 8 cm wide, framing exactly two raised rectangular panels, one upper and one lower, with bevelled borders.
2. Frosted window: exactly one rectangular pane, 30 cm wide and 40 cm tall, centered left to right in the upper panel, its top edge 22 cm below the top of the door, in a thin brass frame.
3. Ventilation grille: exactly one rectangular brass grille, 40 cm wide and 15 cm tall, centered left to right, its bottom edge 12 cm above the bottom, with horizontal angled slats.
4. Handle: exactly one polished brass lever handle near the right edge, 105 cm above the bottom, on both faces.
5. Lock indicator: exactly one small round brass-rimmed indicator, 5 cm in diameter, directly above the handle, showing a plain solid red color.
6. Hinges: exactly three polished brass hinges on the left edge, at 25 cm, 100 cm and 175 cm above the bottom.

MATERIALS:
- Wood: varnished dark walnut (#6A3A22), vertical grain, satin gloss.
- Frosted glass: milky translucent white.
- Brass: polished brass (#C9A24A), faint patina.
- Indicator: solid red (#9E1B1B).
- Clean overall.

STYLE: realistic 1930s European railway carriage joinery.

KEEP OUT: text, letters, pictograms and logos anywhere on the object, including the indicator and the glass.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 9. Toilet

```
3D model reference for Tripo: one single isolated 1930s vintage railway train toilet, shown alone on a plain white background. A white glazed porcelain bowl on a porcelain pedestal, a varnished dark mahogany seat and closed lid, a flat polished brass back plate with a round brass push-button, and a small brass foot pedal at the front of the base.

ISOLATED OBJECT: the image contains only this one toilet, complete, centered and fully visible, on a seamless plain white studio background. All the space around the toilet is empty white. It stands on its own; it is not inside a toilet room, carriage or any interior, and no wall is shown behind it.

ORIENTATION: upright, front view. The front of the toilet (where a person would sit facing forward) faces the camera. Symmetric left to right.

DIMENSIONS: 42 cm wide, 48 cm tall with the lid closed, 60 cm deep from front to back including the back plate. The lid is the highest point of the object.

PARTS:
1. Bowl and pedestal: one continuous rounded white porcelain form, widest at the top rim, narrowing into a pedestal that ends in a flat oval foot.
2. Seat: one varnished mahogany ring seat on the bowl rim.
3. Lid: one varnished mahogany lid, closed, covering the seat, attached at the back with two small brass hinges.
4. Back plate: the back of the bowl ends in one flat vertical polished brass plate, 30 cm wide and 20 cm tall, with exactly one round brass push-button in its center and four screw heads in the corners. This plate is the rearmost part of the toilet.
5. Foot pedal: exactly one small brass foot pedal sticking out 8 cm forward from the bottom front of the pedestal, 3 cm above the bottom.

MATERIALS:
- Bowl and pedestal: white glazed porcelain (#F2F0EA), glossy and smooth.
- Seat and lid: varnished dark mahogany (#5A2E1C), satin gloss, visible grain.
- Back plate, button, hinges and pedal: polished brass (#C9A24A), faint patina.
- Clean.

STYLE: realistic 1930s railway sanitary fittings. The toilet is flushed from the train's roof tank, so it is a compact bowl with only the low brass back plate behind it.

KEEP OUT: a cistern or water tank, and text or logos anywhere on the object.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 10. Sink

```
3D model reference for Tripo: one single isolated 1930s vintage railway lavatory washstand, shown alone on a plain white background. A small white glazed porcelain wash basin on a dark cast iron stand with two legs, two polished brass taps at the back and a brass towel rail across the front of the stand.

ISOLATED OBJECT: the image contains only this one washstand, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white, including the space above the taps. It stands on its own; it is not inside a toilet room, carriage or any interior, and no wall is shown behind it.

ORIENTATION: upright, front view. The front of the basin faces the camera; the taps are at the back. Symmetric left to right.

DIMENSIONS: 50 cm wide, 40 cm deep. The basin rim is 85 cm above the bottom of the legs; the taps rise 12 cm above the rim, so the overall height is 97 cm.

PARTS:
1. Basin: exactly one white porcelain basin, 50 cm wide and 40 cm deep, with a rounded front, a flat back edge, a 6 cm raised splash-back along the back, a bowl 14 cm deep and one round drain in the center. The basin is empty.
2. Taps: exactly two polished brass taps on the back ledge, 20 cm apart, each with a cross-shaped handle topped by a plain white porcelain button, spouts pointing forward over the basin.
3. Stand: one dark cast iron stand under the basin with exactly two straight legs at the front corners, joined by one horizontal crossbar 25 cm above the bottom, each leg ending in a small round foot.
4. Towel rail: exactly one polished brass round rail across the front between the two legs, 60 cm above the bottom. The rail is bare.

MATERIALS:
- Basin: white glazed porcelain (#F2F0EA), glossy.
- Taps and towel rail: polished brass (#C9A24A), faint patina.
- Stand: dark cast iron (#2A2826), matte.
- Clean.

STYLE: realistic 1930s railway sanitary fittings.

KEEP OUT: text, letters and logos anywhere on the object, including the tap buttons.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```

## 11. Bogie

```
3D model reference for Tripo: one single isolated 1930s vintage railway passenger carriage bogie (a two-axle wheel truck), shown alone on a plain white background. Riveted black-painted steel plate side frames, exactly two axles with spoked steel wheels, large leaf springs, coil springs and outside axle boxes.

ISOLATED OBJECT: the image contains only this one bogie, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. The four wheels are the lowest points of the object and rest on nothing but the white background. The bogie is shown on its own, with nothing above it.

ORIENTATION: standing upright on its four wheels, front view looking along the direction of travel, so the long axis points toward and away from the camera. Symmetric left to right and front to back.

DIMENSIONS: 320 cm long (front to back), 220 cm wide (left to right), 105 cm tall. Wheel diameter 92 cm. The two axles are 250 cm apart. The left and right wheels are 143.5 cm apart (standard gauge).

PARTS:
1. Wheelsets: exactly two axles, each carrying exactly two spoked steel wheels, 92 cm in diameter, with 12 spokes each and a flange on the inner side.
2. Axle boxes: exactly four rectangular cast axle boxes, one on the outside of each wheel, each with a hinged lid and four bolt heads.
3. Side frames: exactly two long riveted steel plate side frames, one on each side outside the wheels, running the full 320 cm length, with visible rows of round rivets and two cut-out openings each.
4. Leaf springs: exactly two large semi-elliptic leaf springs, one on each side in the middle of the bogie, made of visibly stacked steel leaves.
5. Coil springs: exactly four vertical coil springs, one above each axle box.
6. Bolster: one heavy horizontal beam across the middle, resting on the leaf springs, with one round center pivot plate on top. This pivot plate is the highest point of the object.
7. Brakes: exactly four cast iron brake blocks pressing against the wheel treads, linked by simple brake rods.

MATERIALS:
- Frames, bolster, springs, axle boxes and brake gear: black painted steel (#1E1D1B), satin, light weathering, brown brake dust near the wheels.
- Wheels: dark steel with bright polished running treads.
- Rivet heads: black paint with slightly worn highlights.

STYLE: realistic 1930s heavy railway engineering.

KEEP OUT: rails or track under the wheels, a carriage body above, and text, numbers or logos anywhere on the object.

TECHNICAL: one clean mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal) with sharp, high-detail textures. Every part is connected to the object.
```
