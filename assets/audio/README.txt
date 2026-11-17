Last Show: approved October sound delivery, Last_Show_Звуки (2).zip.
The supplied audio is in chapter_one/ and indexed by its manifest.json.
SOURCE.txt contains the supplier's full cue sheet and creation/license notes.
The pack contains 163 WAV sources, including six characters' syllables/emotes.
Long ambience/music files are encoded as Ogg Vorbis; short effects/voices keep WAV.
No previous placeholder effects are used.

Runtime: scripts/chapter_audio.gd. Independent Music/Ambience/SFX/Voice/UI buses
all feed Master, controlled by the existing volume slider. Room beds crossfade;
knocks, rigging and NPC steps have independent 3D emitters. Dialogue syllables
follow revealed letters (narrator silent); skip/close/pause stop or pause speech.
Show outro aligns to a 1.071-second beat; applause starts on the final hit.
Dry/wet alternatives are deliberately selected per cue, never layered together.
The full show-outro listening version is retained in the pack but not played over
its loop + ending.

full_game/ adds seven original deterministic cues for roof/home ambience,
contract signing, the knife/key pickups, rope cutting and the jump. Generator:
art_sources/audio/full_game_sounds.py. They supplement the supplied 163 cues
for the newly implemented acts and endings; no placeholder effects remain.

Reimport from the original ZIP:
python art_sources/audio/import_pack.py '/path/to/Last_Show_Звуки (2).zip'
