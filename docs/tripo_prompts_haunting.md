# Tripo prompts: haunting items and the ghost girl

These replace the placeholder shapes in `scripts/gameplay/haunt_item.gd` (haunting and repair
things), `scripts/gameplay/chore_item.gd` (the shift's ordinary work) and the ceiling hatch in
`scripts/gameplay/haunt.gd`. Updated 2026-11-03 after the toolbar/economy work: the terminal is now
fixed with a USB stick, the blocked W.C. needs only the plunger, and the coffee already uses the
existing `enamel_mug` model. The rules are the same as in `docs/tripo_prompts_1930s.md`:
one isolated object on white, the palette below, and a short KEEP OUT line instead of
long negative lists.

| Material | Hex |
|---|---|
| Railway bottle green | `#2B4A40` |
| Cream | `#E6D9B8` |
| White porcelain | `#F2F0EA` |
| Varnished dark walnut | `#6A3A22` |
| Polished brass | `#C9A24A` |
| Dark cast iron | `#2A2826` |

## Tripo settings

- Props: PBR on, texture 2K, 2–4 variants. Send only a clean one.
- The girl: Smart Mesh, ~20k triangles, rigged with the **Mixamo** skeleton, exported as GLB
  in T-pose (same as every passenger).
- Small items get a lot of texture per centimetre, so check that the texture is sharp at
  close range: the player holds these.

## Checklist (in order)

| # | Asset | Where in the game | Max triangles |
|---|---|---|---|
| 1 | Coffee cup and saucer (optional) | Kevin's desk; replaces `enamel_mug` for coffee only | 3,000 |
| 2 | Folded newspaper | Mike's chair, carried to the ghost | 1,500 |
| 3 | Plunger | Sleeping car service room, the blocked W.C. | 2,000 |
| 4 | USB stick | Nightstand in Kevin's compartment, reinstalling the terminal | 800 |
| 5 | Scrubbing brush | Service room chest of drawers, scrubbing a berth's stain | 1,500 |
| 6 | Screwdriver | Service room chest of drawers, the ceiling hatch | 1,500 |
| 7 | Ceiling access hatch | The W.C. end of each passenger car (heating unit) | 4,000 |
| 8 | Cable terminal block | Inside the hatch, the three loose cables | 3,000 |
| 9 | Cage key | On the safe in Mike's room, opens the holding cage | 800 |
| 10 | Dirty bedding bundle | Stripped off a berth, taken to the hamper | 2,500 |
| 11 | The ghost girl (character) | The giggle in the dark, the lunge | ~20,000 |

Clean linen can use the existing `sheet_folded` / `towel_folded` models, so it has no prompt here.

---|---|---|---|
| 1 | Coffee cup and saucer | Kevin's desk, carried to the ghost | 3,000 |
| 2 | Folded newspaper | Mike's chair, carried to the ghost | 1,500 |
| 3 | Plunger | Crew W.C., the toilet clog | 2,000 |
| 4 | Mop | Crew W.C., the puddle | 4,000 |
| 5 | Floppy disk in paper sleeve | Mike's nightstand, reinstalling the terminal | 800 |
| 6 | Screwdriver | Sleeping car service room, the ceiling hatch | 1,500 |
| 7 | Ceiling access hatch | The W.C. end of each passenger car (heating unit) | 4,000 |
| 8 | Cable terminal block | Inside the hatch, the three loose cables | 3,000 |
| 9 | The ghost girl (character) | The giggle in the dark, the lunge | ~20,000 |

---

## 1. Coffee cup and saucer

```
3D model reference for Tripo: one single isolated 1930s railway dining-car coffee cup standing on its matching saucer, shown alone on a plain white background. Thick white porcelain with a bottle green band and a thin gold line, filled with black coffee.

ISOLATED OBJECT: the image contains only this one cup on its one saucer, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. No spoon, no sugar, no table, no tray.

ORIENTATION: upright, seen from the front and slightly above, so the coffee surface inside the cup is visible. The cup handle points to the right.

DIMENSIONS: saucer 14 cm across and 2 cm tall. Cup 8.5 cm across at the rim, 7 cm tall, standing in the center of the saucer. Overall height 8.5 cm.

PARTS:
1. Saucer: round, with a shallow well in the center that the cup foot sits in, and a gently raised rim.
2. Cup: a rounded bowl narrowing to a short foot ring, with a thick rolled rim.
3. Handle: one closed loop handle, large enough for one finger, joined smoothly to the cup at top and bottom.
4. Coffee: a flat, dark brown-black liquid surface 1 cm below the rim, with a faint lighter ring at the edge.
5. Decoration: one bottle green band 6 mm wide just below the cup rim and one around the saucer rim, each edged by a thin gold line.

MATERIALS:
- Porcelain: warm white (#F2F0EA), glossy glaze with soft reflections.
- Band: bottle green (#2B4A40), glazed. Gold line: polished gold, thin.
- Coffee: glossy dark brown-black liquid.
- Light wear: a few fine scratches on the saucer well. Clean overall.

STYLE: realistic 1930s European railway tableware, heavy and practical.

KEEP OUT: text, logos and crests on the china.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures, clear separation between porcelain, gold line and coffee. The cup is joined to the saucer.
```

## 2. Folded newspaper

```
3D model reference for Tripo: one single isolated 1930s broadsheet newspaper, folded in half and then in half again, lying flat, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one folded newspaper, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. It lies on nothing: no table, no hand.

ORIENTATION: lying flat, seen from the front and above at about 45 degrees. The folded spine runs along the left edge; the open page edges are on the right.

DIMENSIONS: 30 cm wide, 21 cm deep, 1.2 cm thick at the fold, thinning to 0.8 cm at the open edges.

PARTS:
1. A stack of thin newsprint pages with slightly uneven, soft open edges, the individual sheets just visible along the right edge.
2. A rounded fold along the left edge.
3. The top page: a wide black masthead band along the top third (dark heavy shapes that look like a title, not readable letters), then four narrow columns of fine grey print texture, one grey halftone photograph rectangle and two bold headline bars.
4. A slight curl at the top right corner.

MATERIALS:
- Newsprint: off-white aged paper (#E6D9B8 to slightly greyer), matte, fine fibre texture.
- Print: soft black and grey ink, slightly blurred like letterpress on cheap paper.
- Light handling: faint creases and a softened fold. Clean overall.

STYLE: realistic 1930s Central European daily newspaper.

KEEP OUT: readable words, modern colour photos.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, normal), sharp high-detail print texture on the top page. One connected object.
```

## 3. Plunger

```
3D model reference for Tripo: one single isolated old-fashioned toilet plunger, black rubber cup on a straight varnished wooden handle, standing upright, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one plunger, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. No toilet, no bucket, no floor.

ORIENTATION: standing upright on the rim of its rubber cup, handle pointing straight up, front view.

DIMENSIONS: overall height 62 cm. Rubber cup 15 cm across at the open rim, 7 cm tall. Handle 2.6 cm in diameter.

PARTS:
1. Rubber cup: a bell shape, wide and open at the bottom, narrowing to a thick neck at the top, with a slightly rolled bottom rim.
2. Handle: one straight round wooden dowel pushed into the neck of the cup, ending at the top in a smooth rounded tip.
3. A thin metal ferrule ring where the handle enters the rubber.

MATERIALS:
- Rubber: matte black with a faint satin sheen, a little greyish wear on the rim.
- Handle: varnished dark walnut (#6A3A22), straight grain, worn lighter near the top where it is held.
- Ferrule: dull steel.

STYLE: realistic 1930s utility tool, used but clean.

KEEP OUT: text, labels, water, dirt stains.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures. Handle and cup are joined.
```

## 4. USB stick

```
3D model reference for Tripo: one single isolated plain USB memory stick with its cap off and a small paper tag on a loop of string, lying flat, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one USB stick with its tag, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. The cap is not shown.

ORIENTATION: lying flat, seen from above at about 45 degrees. The metal connector points right; the tag lies to the left of the stick.

DIMENSIONS: stick 5.5 cm long, 1.9 cm wide, 0.9 cm thick, connector 1.2 cm long. Tag 4 cm by 2.5 cm.

PARTS:
1. Body: a rounded rectangular dark grey plastic body with a small loop hole at the back end.
2. Connector: a standard rectangular steel USB plug with two small square holes on top.
3. Tag: a cream card tag with a reinforced hole, tied through the loop hole with a short thin string, with a few handwritten pencil scribbles (not readable).

MATERIALS:
- Body: dark grey plastic (#2A2826), satin, a few scuffs.
- Connector: brushed steel.
- Tag: cream card (#E6D9B8), matte, slightly bent. String: off-white cotton.

STYLE: realistic, plain and a little worn, an office spare.

KEEP OUT: brand names, logos, readable words, lights.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures. The tag and string are joined to the stick.
```

## 5. Scrubbing brush

```
3D model reference for Tripo: one single isolated old-fashioned wooden scrubbing brush with stiff natural bristles, lying bristles-down, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one brush, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. No bucket, no soap, no water.

ORIENTATION: lying bristles-down, seen from the front and above at about 45 degrees, the long side facing the camera.

DIMENSIONS: 22 cm long, 7 cm wide, 7 cm tall including the bristles (wooden block 2.5 cm thick, bristles 4.5 cm).

PARTS:
1. Block: a solid wooden block shaped like a flattened boat, with pointed rounded ends and a shallow finger groove along each long side.
2. Bristles: dense tufts of stiff natural fibre set in rows, slightly splayed and worn unevenly at the tips.

MATERIALS:
- Block: unvarnished beech wood, pale and water-stained darker at the bottom edge.
- Bristles: natural tan fibre, darker and a little matted at the tips.

STYLE: realistic 1930s household cleaning brush, used but clean.

KEEP OUT: text, logos, a handle.

TECHNICAL: one clean closed mesh, game-ready topology (the bristles as solid tufts, not single hairs), PBR textures (base color, roughness, normal), sharp textures. One connected object.
```

## 6. Screwdriver

```
3D model reference for Tripo: one single isolated old-fashioned flat-blade screwdriver with a varnished red wooden handle, lying on its side, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one screwdriver, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white.

ORIENTATION: lying horizontally on its side, handle on the left, blade tip pointing right, seen from the front and slightly above.

DIMENSIONS: overall length 22 cm. Handle 10 cm long and 3 cm across. Steel shank 12 cm long and 7 mm across.

PARTS:
1. Handle: a fluted wooden handle with eight shallow grooves, a rounded end and a brass ferrule ring where the shank enters.
2. Shank: a round steel rod ending in a flat blade tip, 7 mm wide.

MATERIALS:
- Handle: varnished deep red wood, glossy, with small chips showing lighter wood.
- Ferrule: polished brass (#C9A24A).
- Shank and blade: polished steel, slightly scuffed at the tip.

STYLE: realistic 1930s tradesman's tool.

KEEP OUT: text, logos, other tools.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures. All parts are joined.
```

## 7. Ceiling access hatch

```
3D model reference for Tripo: one single isolated 1930s railway carriage ceiling access hatch for a heating unit: a rectangular louvred panel in a brass frame, seen from below as if looking up at the ceiling, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one hatch with its frame, complete, centered and fully visible, on a seamless plain white studio background. All the space around the frame is empty white. There is no ceiling around it.

ORIENTATION: the panel faces the camera flat (as seen looking straight up from below). The hinge is along the top edge of the image; the latch is along the bottom edge.

DIMENSIONS: outer frame 100 cm by 64 cm, 3 cm deep. The hatch panel inside it is 92 cm by 56 cm and 2 cm thick.

PARTS:
1. Frame: a flat polished brass frame, 4 cm wide, with a slot-head brass screw in each corner.
2. Panel: a cream painted steel panel with two rows of horizontal louvre slats (eight slats per row), angled so the slots look dark inside.
3. Hinge: one long piano hinge along the top edge.
4. Latch: two slot-head screw fasteners along the bottom edge, plus a small brass pull ring in the middle.
5. Two small round ventilation grilles of punched holes in the corners of the panel.

MATERIALS:
- Panel: cream enamel paint (#E6D9B8), satin, slightly yellowed, with faint dust in the louvres.
- Frame, screws, hinge and ring: polished brass (#C9A24A) with faint patina.
- Inside the louvre slots: very dark.

STYLE: realistic 1930s European passenger carriage fitting, Art Deco influenced.

KEEP OUT: text, labels, warning signs.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures. Frame and panel are separate parts that touch along the hinge.
```

## 8. Cable terminal block

```
3D model reference for Tripo: one single isolated 1930s electrical terminal block with three loose insulated cables, red, yellow and black, hanging down from it, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one terminal block with its three cables, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white.

ORIENTATION: the block is at the top, its face toward the camera. The three cables hang straight down from its underside, side by side, each ending in a bare brass plug, with the plug tips 25 cm below the block.

DIMENSIONS: block 30 cm wide, 10 cm tall, 8 cm deep. Each cable 1.5 cm thick.

PARTS:
1. Block: a black bakelite base on a dark iron mounting plate with four bolt heads, carrying three brass screw terminals in a row across its front, each with an empty socket hole below it.
2. Cables: three cloth-braided cables (left red, middle yellow, right black) coming out of the block's underside with slight natural curves.
3. Plugs: one cylindrical brass plug on the end of each cable, with a ridged grip.

MATERIALS:
- Block: glossy black bakelite. Mounting plate: dark iron (#2A2826), matte.
- Terminals and plugs: polished brass (#C9A24A), faint patina.
- Cables: woven cloth insulation, red, mustard yellow and black, slightly frayed at the ends.

STYLE: realistic 1930s railway electrical fitting.

KEEP OUT: text, warning labels, sparks.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures, clear separation between bakelite, brass and cloth. All parts are connected.
```

## 9. Cage key

```
3D model reference for Tripo: one single isolated large old iron key on a ring with a brass tag, lying flat, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one key with its ring and tag, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white.

ORIENTATION: lying flat, seen from above at about 45 degrees. The key blade points right; the ring and tag are on the left.

DIMENSIONS: key 11 cm long, bow 4 cm across, shaft 0.8 cm thick. Ring 4 cm across. Tag a brass disc 3.5 cm across, 2 mm thick.

PARTS:
1. Key: a round open bow with a decorative trefoil cutout, a plain round shaft and a chunky bit with two square notches.
2. Ring: a plain split steel ring through the bow.
3. Tag: a round brass disc hanging from the ring, with a stamped border and a stamped number shape in the middle (not a readable number).

MATERIALS:
- Key: dark forged iron (#2A2826), worn shiny on the bow and the bit edges.
- Ring: dull steel.
- Tag: polished brass (#C9A24A), patina in the stamped grooves.

STYLE: realistic 1930s railway lock-up key, heavy and old.

KEEP OUT: readable text and numbers, other keys.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, metallic, normal), sharp textures. Key, ring and tag are connected.
```

## 10. Dirty bedding bundle

```
3D model reference for Tripo: one single isolated bundle of used bed sheets and a pillowcase rolled up tightly together, lying on its side, shown alone on a plain white background.

ISOLATED OBJECT: the image contains only this one bundle of bedding, complete, centered and fully visible, on a seamless plain white studio background. All the space around it is empty white. No bed, no basket, no hamper.

ORIENTATION: lying on its side, the long axis left to right, seen from the front and slightly above.

DIMENSIONS: about 45 cm long, 28 cm across, 22 cm tall.

PARTS:
1. A rolled bundle of crumpled white cotton sheets with soft deep folds and creases.
2. One corner of a sheet hanging loose from the right end, and the striped edge of a pillowcase visible in the middle of the roll.

MATERIALS:
- Cotton: greyish off-white, matte, with soft creases, a few faint yellowish-grey stains and a dull blue stripe along the pillowcase edge.

STYLE: realistic used railway sleeping-car bedding, rumpled but not disgusting.

KEEP OUT: blood, text, a laundry bag.

TECHNICAL: one clean closed mesh, game-ready topology, PBR textures (base color, roughness, normal), soft fabric shading. One connected object.
```

## 11. The ghost girl (character)

She is made like every passenger (Smart Mesh, Mixamo rig, T-pose). The game makes her pale and
translucent itself, so she is modelled as an ordinary girl with ordinary colours. Clear eyes and
a closed mouth matter: Claude adds the talking face and lip sync afterwards.

```
3D character model reference for Tripo: one full-body realistic girl, about 8 years old, from 1930s Central Europe, standing in a T-pose, shown alone on a plain white background.

ISOLATED CHARACTER: the image contains only this one girl, complete from head to shoes, centered and fully visible, on a seamless plain white studio background. All the space around her is empty white. She holds nothing.

POSE: a strict T-pose. Arms straight out to the sides at shoulder height, palms facing down, fingers straight and slightly apart. Legs straight, feet shoulder-width apart, pointing forward. Head straight, looking directly into the camera. Front view, symmetric.

BODY: slim child proportions, 125 cm tall, a slightly large head for her age, small shoulders.

FACE: a calm, neutral expression with the mouth closed, lips together and relaxed. Large, clear, open eyes with visible whites and dark grey-blue irises looking straight ahead, well-defined eyelids, natural thin eyebrows. Pale skin with a faint pink in the cheeks. A small nose. Nothing covers the eyes or the mouth.

HAIR: dark brown hair in a short 1930s bob, chin length, with a straight fringe ending above the eyebrows, and a white satin ribbon tied in a bow on the right side. The hair sits close to the head; no strands fall over the face.

CLOTHES:
1. A knee-length pale blue cotton dress with a dropped waist, a white rounded Peter Pan collar, short puffed sleeves and a narrow pleated skirt that hangs straight (not flared wide).
2. A thin white cotton belt sash at the dropped waist.
3. White knee socks.
4. Black patent leather Mary Jane shoes with one strap and a small button.

MATERIALS: soft cotton with fine weave texture, a glossy satin ribbon, glossy patent leather shoes. Light, old-fashioned wear: the dress slightly faded, a small mended patch on the hem.

STYLE: realistic, a little old-fashioned, like a girl in a 1930s family photograph. Gentle and ordinary, not scary.

KEEP OUT: a hat, a coat, gloves, glasses, a toy in her hands, jewellery.

TECHNICAL: one clean watertight mesh suitable for auto-rigging with a humanoid (Mixamo) skeleton, game-ready topology about 20,000 triangles, separate fingers, clothes tight enough not to bridge between the legs, PBR textures (base color, roughness, normal), sharp high-detail texture on the face and eyes.
```
