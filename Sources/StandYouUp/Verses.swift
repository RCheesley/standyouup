// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Sīlavāpi Cheesley and contributors

import Foundation

/// Short public-domain renderings of verses from the Dhammapada, shown at random
/// on the break overlay. These are brief paraphrases of an ancient text.
let dhammapadaVerses: [(text: String, ref: String)] = [
    ("We are what we think. All that we are arises with our thoughts. With our thoughts, we make the world.", "Dhammapada, v.1"),
    ("Health is the greatest gift, contentment the greatest wealth, and trust the finest kinship.", "Dhammapada, v.204"),
    ("As a solid rock is not shaken by the wind, so the wise are unshaken by praise or blame.", "Dhammapada, v.81"),
    ("Though one may conquer a thousand times a thousand in battle, greater still is the one who conquers themselves.", "Dhammapada, v.103"),
    ("Let one not look to the faults of others, but to one's own deeds, done and undone.", "Dhammapada, v.50"),
    ("Hatred does not cease by hatred, but only by love; this is the eternal rule.", "Dhammapada, v.5"),
    ("Better than a thousand hollow words is one word that brings peace.", "Dhammapada, v.100"),
    ("You yourself must strive. The Buddhas only point the way.", "Dhammapada, v.276"),
    ("To do no evil, to cultivate good, to purify the mind — this is the teaching of the awakened.", "Dhammapada, v.183"),
    ("Irrigators guide the water; fletchers shape the arrow; the wise shape themselves.", "Dhammapada, v.80"),
]

func randomVerse() -> (text: String, ref: String) {
    dhammapadaVerses.randomElement() ?? dhammapadaVerses[0]
}
