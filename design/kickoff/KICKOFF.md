HEXHUNT — KICKOFF PROMPT FOR CLAUDE CODE
=========================================


0. ORDER OF OPERATIONS
----------------------
Do these in order. Do not write code or create lanes before step 3 is approved.

  1. Read the reference projects listed in section 2.
  2. Interview me (section 3). One question at a time. Stop when section 3 is answered.
  3. Write PLAN.md from the interview. Ask my permission to begin the build.
  4. Only then set up the lanes in section 6.

Verify key decisions explicitly as we go. If a later instruction contradicts
PLAN.md, say so and ask which wins before acting.


1. PREMISE
----------
We are building Hexhunt: a co-op hunting game. A small party, equipped with
medieval weapons and elemental attunement, explores a world and challenges
rampaging monsters.

Party size: 1-4
Number of monsters in the first playable: 4

This is live action. It is right click to move, left click to target; q, w, e, r for weapon actions. 



2. REFERENCE PROJECTS AND STANDARDS
-----------------------------------
Read these before the interview. Reuse what fits; do not port blindly.

  Black | White      ..\Black White
                     Source of: the four-document system, the DECISIONS log,
                     the LEDGER four-test rule, the rules core (node-free,
                     seeded, one formulas module), script-built meshes with
                     manifest + preview + test, the Giant fight, the mobile
                     layout, the self-test and CI gate.

  Gamers Gauntlet    ..\Gamers Gauntlet
                     Source of: the raid built on the Giant, the WebGL shim,
                     the record of what a room of friends found boring to watch.

  The Temporal Sea   ..\Temporal Sea
                     Source of: the element/wish design, the tile-effect matrix,
                     the ability tag vocabulary, the hex renderer with elevation.

The above references are not defining. They are to be used as references where useful. This new project will take inspiration from the defined system of: black | white’s elemental interactions, and gamers Gauntlet MMO/OSRS mechanics and systems. 

There should also be documentation In gamers gauntlet that aid in developing maps, models, and other involved systems. 
  
Documentation standard, carried over as-is, reference above folders. 
  CLAUDE.md     root index, one paragraph stating the game, pointers to guide/
  HANDOFF.md   
  LEDGER.md     tracked items only if discrete, changeable, costly to forget,
                and not already guarded by a test
  DECISIONS.md  numbered rows: date, rule, who ruled (Author / Claude / both),
                why, status. Superseded rows marked in place, never deleted.
  guide/        the leaves CLAUDE.md indexes

  PLAN.md       phases with gates; I check each gate before the next phase

Rule for Claude's own calls: minor ambiguities are yours to decide in favour of
fun or emergent play. Log every such call in DECISIONS.md as &quot;Claude, decided&quot;. Anything you would want feedback prior to a resolve, ask me. 

3. INTERVIEW
------------
User basically answered some existing interview questions, the below section’s format is horrible but may provide good guidance or tear down of ambiguities. Clarify if required. . Record answers in PLAN.md section 0.

  a. This is a real time game 
  b. For me to playtest and share online with friends. 
  c. Co-op is possible at end build but is not mandatory. Players should be able to play independently.
  d. The deliverable is a game 
  e. Which parts of Black | White carry over: rules core, and meshes,   
  g. What is the monster to the player: a puzzle with telegraphed moves, a  boss with phases, or an opponent with its own AI?(mostly just a boss with phases and telegraphed moves.  

  h. What does a hunt look like start to finish, in one paragraph?
You explore the open world map, you see a disturbance in the water, you approach and a monster jumps out, angry. A short cutscene, you prepare your weapons, skills, equippables, elemental attunements, and you begin the fight ,  you are in a 100x100ft arena and the opponent is a big monster boss. They start to attack you with ranged projectiles and you can dodge them and set your own element on the ground. They will charge at some point, interacting with your own elements. You have to deal damage and trigger reactions to whittle the enemy down as they try to tackle you, spin on you. Use the environment to your advantage. Upon victory you gain equipment or a skill progression. 
  i. What is the smallest thing I can open and play that proves the idea?  A single fight in Godot. 
     That is Phase 1's gate.


4. ROLE AND QUALITY BAR
-----------------------
Act as Lead Technical Artist, Animation Engineer and Engine/Tools Developer.

Art direction: one coherent visual language for silhouettes, proportions,
material roles, contours and colour hierarchy. Every unit and monster readable
at game scale and still deliberate when magnified. Controlled palette with
logical material and shadow roles. Seamless joints, correct inner outlines,
correct depth sorting of near and far limbs.

Animation: weight, balance, intent and personality. Posing, anticipation,
timing, arcs, layering, follow-through and contacts. Transitions, direction
changes and speed changes held to the same bar as loops.

Technical: data, generation, posing and rendering decoupled behind clear
contracts. Lifecycle, cleanup, error states, versioning and reproducible
output handled. The framework must be usable in another Godot game without
the workshop interface.

Tooling: parameters respond predictably, undo/redo preserves work, presets and
exports are reliable, progress and errors are visible. The UI must support
focused work by a developer or artist.

Verification: verify technical and visual results, name specific shortcomings,
fix root causes. Do not forge screenshots, test results or performance figures.


5. ENGINE AND VERIFICATION
--------------------------
Engine: Godot 4.7 standard build, GDScript only, no plugins. This matches every
prior project. 

Required from the first session:
  - Verify build, resource import and runtime startup with the real Godot
    binary:  godot --headless --path . --import
  - Implement a project flag:  godot --headless --path . -- --self-test
    It returns a structured report and a non-zero exit code on failure.
    --self-test is ours, not a Godot flag.
  - Visual verification by actual renders (software rendering or virtual
    display), not headless startup alone. Capture interface renders and
    animated samples where the environment allows.
  - Any test that cannot run in the environment is listed as open, with the
    exact local command I run to close it.


6. LANES
--------
In Claude Code these are parallel sessions, each in its own worktree, with an
owned file set and a reserved block of DECISIONS numbers. Merge to dev. No
lane edits another lane's files. Define lanes only after PLAN.md is approved.

Use what gamers gauntlet did for modeling equipment and environments. 
Use what black white did for modeling character models and movement. See if you can apply that to monsters. 

  Lane A — Weapons
    Expand the low-poly weapon set the units equip.
    Weapons to add: glaive style lance, dual daggers, bow. Use black whites roster as a baseline. But gauntlet test them to the below references
    Each weapon: model, manifest row, preview render, test, equip clip.




The karambit should be sword sized and big. 










  Lane B — Weapon animation
    Clips that use Lane A's weapons.
    Clip list per weapon: wielded idle, forward strike, sweep, spin; jump, jump and attack,
Specialized clip: dagger forward dive/corkscrew, bow kneeling shot, lance plant, lance slam, lance guard

  Lane C — Map tooling
    Use gamers gauntlet map generator to suit hexhunt's needs. 
If there are any changes, list
    (arena size, monster spawn, elevation, hazards) before any map is made.
    Changes suggested: Shrink ⁠GKExtractForest⁠ from 300x300m down to a 35x35m (~100x100ft) enclosed boss arena with a visual skirt beyond the boundary.  
 Logical Hex Underlay: Lay an invisible odd-r hex grid (⁠BWHex⁠ from Black | White) mapped onto the arena floor's heightmap. Uncharged hexes are invisible so the natural pond/grass/cave floor shows through; charged or marked hexes render Black | White's procedural element shaders flush with the terrain surface.
Boss Telegraph Layer: Monster attacks telegraph by highlighting the exact target hexes (or smooth ground danger circles snapped to the arena floor) before impact.

 Add environmental interaction nodes per biome: water depth/lilypad cover for monster dive, destructible rock pillars for the Cave, heat vents/lava pools for monster in the Caldera, and sunlit patches for monster in the Grassy Glade.  


  Lane D — Maps
    Author these maps with the gauntlet style editor, 

    Shallow lilypad pond: a nice shallow lake easily walkable; lilipads decorate the arena, a beautiful sunny day in the background. Add some flowers and such. Maybe a lilipad or two to hide behind. 

cave:
Plenty of elevation changes, no ceiling is fine. Noticeably dark
Plenty of rocks and pillars as obstacles.  


Grassy glade
Minor elevation, some trees as obstacles. 


Volcanic Caldera



  Lane E — Units and monsters
    Model and animate these as low-poly 3D:
    Player units: check current models to see if we need any more
build a modular Monster Rig Builder (similar to ⁠BWCharacter⁠ + ⁠GKMesh⁠ primitives: articulated spine/tail chain, jaw bone, quadruped/biped leg IK, and wing/back sockets) and gate Phase 1 on just ONE monster first (e.g., swampfang in the Shallow Lilypad Pond, since Section 3h specifically describes seeing a disturbance in the water and a monster jumping out!). Once 1 monster + 1 arena feels 10/10, unleash the parallel lanes afterwards. 

Images are reference only and show the art direction and inspiration  in my eyes. 

   
Colambros

Body: Long and low, like a hyena stretched into a lizard. Strong rear legs lie a kangaroo. Almost vestigial front legs like a kangaroo. likes to walk on its rear legs. A ridge of long, quills runs down the spine and sways when it runs.
Palette: Rust-red hide, ash-white belly, bone-coloured quills that darken toward the tips.
Calm: Sprawls in the sun and gnaws loose quills off its flanks, spitting them out.
Aggravated: Runs a lap of the arena and charges in a straight line if you're too far away. After a  lap  its quills start to smoulder, and from then on every charge leaves a burning trail.
Attacks: Dirt-scrape before a charge, headlong charge, quill rattle-roar, tail lash, bite, ember spit, leap and stomp. The breakdance becomes a back-roll that scatters smouldering quills.
Tells: The dirt-scrape is the charge warning. Glowing quill tips mean the trails are live.
Weak point: Spent quills. After the roll it's bald along the spine for a few seconds.
Status: Burn.
Feel: The one fast monster.
 


Colambros animations; foot kicking up dirt; headlong charge, fire discharge roar, tail whip and strike, basic bite. Fire spit, leap and stomp, breakdance, more if you like. These will be turned into telegraphed attacks the user shall try to avoid. 

If there is no offensive threat on Colambros he likes to sleep and relax and pick at his tail spikes. 
Colambros  likes to run around the arena and charge the user in a straight line if it’s too far away. He has harnessed fire and can leave behind fire trails once charged and his tail starts to glow. He will try to get up close and bite and tail whip. 





Rimeslithe
Body: Huge, hunched and creepy crawly, with long forearms and a dragon  head. Clusters of ice crystal grow from its shoulders and back.
Palette: Dark slate-blue hide. The crystals start smoky grey and turn bright pale cyan as it chills.
Calm: Seeks out cold vents or shade and sits in them, frosting over until the crystals glow.
Aggravated: Exhales freezing mist across the arena, chilling the ground into slow terrain. Fights at medium and close range.
Attacks: Frost beam, cold-wave ground slam, shoulder charge, roar, bite, arm swipe, mist breath. Meteor drop becomes ripping a crystal off its back and hurling it high, where it shatters into a hail zone. Melting rocks becomes freezing pillars until they crack and burst.
Tells: Crystal brightness shows how much cold it has stored. It plants both fists before a slam.
Weak point: Hit it near heat, or break its crystals, to drain its stored cold.
Status: Slow, then freeze.


   Rimeslithe animations: ice beam, ice waves, headlong charge, ice discharge roar, basic bite, arm swipe, light breath, meteor drop, freezing rocks, more if you like. 

Rimeslithe likes to go near cold and cold up visibly turning coolr, when aggravated, reshiram will begin breathing ice about the arena and expending his energy freezing up the surroundings and trying to ice burn the player. Reshiram is powerful and large and will attack the character from both medium and close range.
Give it light element too why not. 





Spirewalker
 Body: Broad, flat and six-limbed, between a crab and a horned lizard. A dense bed of tall copper reeds covers its back, and short bristles line both forearms.
Palette: Mustard and dusty ochre hide, copper reeds, violet arcs between the reeds when charged.
Calm: Sits motionless with its reeds raised, soaking up static from the sky. Small sparks crawl between the reeds.
Aggravated: Jumps to squash you, swipes, bites. Its forearm bristles fire sparking barbs when swung fast, and the reeds lash out like whips.
Signature: It shakes charged pollen from the reeds. The cloud slows you, and lingering in it paralyzes.
Attacks: Pollen shake, barb throw, forearm punch, leaping squash, bite, reed lash, tail drag.
Tells: The reeds fold flat just before the squash. Violet arcs mean pollen is coming.
Weak point: The reeds. Burn or cut them and it loses the pollen.
Status: Paralysis, dark poison.

Spirewalker animations: thunder breath dark breath, thorn throw, arm punch, leaping bite, bite, spore spread, tail whip, vine whip

Spire likes to sit still and soak up the lightning. If aggravated it will try to jump and squish the player, it will swipe with its arms and try to bite you; its arms can spray thorns if waved fast enough, and its vines on its back can try to strike you. It’s plant on the back can spread wind effect and spores that slow your movement and hit you. 


Swampfang
Body: A long, eel-bodied salamander with a frilled gill collar. Strong front legs, small weak hind legs, and a flat paddle tail.
Palette: Mottled blue and lavender purple, with a red frill that flares when it's angry.
Calm: Floats half-submerged among the lily pads, only the frill showing.
Aggravated: jumps up above the lily pads Rushes you to get close. Its rear is weak, and if you attack from behind it tries to bite backward and can't reach. Out of range, it sprays dark-laced water. Close in, it builds momentum into a death-roll spin.
Threatened: Dives under the lily pads, swims, then surfaces somewhere else and thrashes, spreading dark water.
Attacks: dark spray, water jet, thrash splash, frill roar, death-roll spin, dive, swim, surface lunge.
Tells: The frill flares before a spray. Ripples under a pad mark where it will surface.
Weak point: The rear and hind legs.
Status: dark to poison and water and ice. .



Swampfang:  animations, ice breath, water breath, wave splash, roar, spin out, dive, swim

Gator likes to rush towards you as possible to get into close range, its rear is relatively weak and it will try and fail to bite backwards if you are attacking its rear. It will spray water and ice at you if you are out of range or its jaws and can gain enough momentum to spin in a dangerous circle. If threatened it can dive under the lift pads and swim around, then pop up and start splashing waves and spreading water and ice. 

 Per monster: silhouette readable at game scale, calm idle, aggravated idle, enrage roar; roar; a hit reaction, a stagger, a collapse ,death, walking. 

The animations should feel weighty and slow and telegraphed maybe with ground circles representing their danger area. The monsters should not feel fast. Except maybe amparos. 

The monsters are wielding their weight, size and strength 




Add, merge or cut lanes if the interview changes the shape. Say why in
DECISIONS.md.


The game is third person MMO style. With movement like runescape. And kiting and attacks like league of legends. 

The UI will be similar to below reference. Each weapon has 4 basic skills that can be modified upon getting a monster drop. 



Dagger:
Q: Flourish (unit spins dealing damage in a large aoe and applying their element to the area) 3s cooldown. 
W: elemental exchange (unit throws daggers in the air, and attunes to backup element.)
E: daggerleap (unit jumps and spins and leaps toward mouse location leaving behind a trail of their element) 6s cooldown
R: Knifedance (unit takes 25% damage while applying 2 elements in sequence each second for up to 6  seconds) 15s cooldown

Lance:
Q: pierce (unit stabs forward applying their unit in a line towards their cursor) 3s cooldown
W: elemental exchange  (unit plants spear into earth, and attunes to backup element)
E: Guard (unit blocks for 2s. Any hit will trigger a stronger pierce toward the enemy)
R: Eruption (unit vaults towards mouse and upon landing explodes in a massive eruption of their element)

Bow: 
Q: energized shot (long distance projectile following mouse location, drawing the element as it passes forward.) 3s cooldown
W: elemental exchange (unit flips their quiver, and attuned to backup element)
E: arcing shot (sends a lobbed elemental bomb at target location, exploding in a burst of chosen element) 
R: Arrowstorm (unit shoots into the air,  jumps very high, (movement input is still applicable and unchange) becomes untargetable, and drops down after 2 seconds triggering a massive downfall of arrows and elements.)

When a monster hits you; your character will be staggered based on the strength of the strike. Your character can be poisoned, paralyzed and burned. Also poison is an aspect of dark now. 

Maps wil interact with the hex max as follows:
: Discrete hex grid under a 3D environment (or invisible logical hex cells that light up with Black | White's procedural fire/water/ice/lightning shaders when painted). That way, you literally drop Black | White's deterministic element reaction math (⁠Overheat⁠, ⁠Fuse⁠, ⁠Glaze⁠, ⁠Douse⁠) straight into ⁠src/core⁠ without having to invent complicated 2D polygon-overlap math for puddles! 
Movement is described as follows. 
True-Hex Precision: In OSRS, you have a &quot;true tile&quot; outline under your character and clicks snap cleanly to the grid while the character model glides smoothly across the floor. In Hexhunt, instead of square tiles, you have a True Hex outline under your feet! You click a hex to run there, you see the exact hexes the monster's attack is about to slam, and you &quot;hex-skate&quot; around Gator or Ampharos while weaving ⁠Q, W, E, R⁠ abilities.  
cCamera: Free-rotating, zoomable third-person orbit camera centered on the player (OSRS style, reusing ⁠OsrsView⁠ / Black | White's orbit camera). Drag middle-mouse (or hold RMB / arrow keys) to orbit and pitch; scroll wheel to zoom. The camera is angled so both the giant monster's silhouette and the surrounding ground hexes are clearly readable at all times
Hex-Snap Movement: Movement and positioning operate on the logical hex underlay (inspired by ⁠OsrsSim⁠ from Gamers Gauntlet, adapted to ⁠BWHex⁠ from Black | White). Clicking a ground hex sets your path destination; your logical position steps hex-by-hex while your 3D character model glides and animates smoothly between hex centers. Draw a subtle True Hex outline under the player's current logical hex and destination hex (just like the OSRS true-tile indicator in ⁠G36⁠).
Targeting &amp; Skills (⁠Q, W, E, R⁠): Clicking a monster sets it as your active target (and walks you into weapon range to basic-attack, OSRS style). Pressing ⁠Q, W, E, or R⁠ fires your weapon actions: directional/leap skills (⁠Q⁠, ⁠E⁠, ⁠R⁠) aim at the hex under the mouse cursor, while ⁠W⁠ (⁠Elemental Exchange⁠) swaps to your backup element in place.
HUD: Clean bottom action bar (⁠Q, W, E, R⁠, HP/Stamina orb, active + backup element indicators) inspired by the reference UI, keeping the screen uncluttered so ground telegraphs and elemental hexes take center stage.
Poll and response rate should be close to 30hz. Worked on gamers gauntlet mmo modules so why not. 

Borrow sound effects from the previous games. 
Audio will be brand new. Head into the audio Claude playground directory and give me 4 or 5 4 bar repeating drumbeats at 120 bpm. Pair those with some midi chord progressions and I’ll I’d it together and provide a melody. 

Re: upgrades from bosses. These should be strong modifiers to your current weapon, and its abilities. 
Each ability has 3 upgrade slots. 

Examples: 
elemental exchange now gives you 1s of immunity 
Elemental exchange now explodes around you in a large radius 
Energized shot now applies element x2 in a line. 
Arcing shot now explodes twice. The second explosion results in 6 smaller elemental application in a larger radius. 
Daggerleap now releases 3 fast moving projectiles homing toward monster within 20ft. These projectiles paint the ground with the element you had upon cast as they travel. 
Your pierce now has triple width. 


7. GATE
-------
When PLAN.md is written, stop and ask my permission to start the build.
Nothing in section 6 begins before that answer.
