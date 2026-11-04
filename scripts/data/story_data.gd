class_name StoryData
extends RefCounted
## Story content: the intro, the recurring characters, the milestones and the daily and
## weekly challenge templates. Story (the autoload) runs them; this file is just the words
## and numbers, so writing new beats doesn't mean touching game logic.

# --- Intro --------------------------------------------------------------------------
# Shown once on your first game, before the tutorial. [title, text]
const INTRO := [
	["Three weeks ago",
		"The Mega-Mart distribution center replaced your whole shift with robots that don't take lunch breaks.\n\nYour last paycheck covered one month of rent. Then it didn't."],
	["Plan B",
		"So here you are in New Castlewood County with $140, a duffel bag, and a rented room at Dottie's Boarding House.\n\nDottie is kind. Dottie also wants $950 on the first of the month."],
	["The Punta",
		"Your cousin Ray sold you his 1995 Fiot Punta GT on an IOU: $1,200, \"whenever you can, but like, soon.\"\n\nIt has 187,000 miles, a cassette deck, and an oil light that's been on since the Clinton administration."],
	["The hustle",
		"Five gig apps. One phone. Zero bosses (unless you count the algorithm).\n\nPay back Ray. Make rent. Get a better car. Get your own place. Maybe, someday, a house with a yard.\n\nTime to hustle."],
]

# --- Recurring characters -------------------------------------------------------------
# kind: "contact" only texts you; "rider" shows up as a regular passenger; "customer" places
# regular delivery orders to the same house. Lines are picked at random.
const NPCS := {
	"mom": {"name": "Mom", "kind": "contact", "color": Color(0.95, 0.6, 0.75)},
	"ray": {"name": "Cousin Ray", "kind": "contact", "color": Color(0.95, 0.7, 0.3)},
	"dottie": {"name": "Dottie", "kind": "contact", "color": Color(0.7, 0.85, 0.55)},
	"mari": {"name": "Mari (fellow driver)", "kind": "contact", "color": Color(0.45, 0.8, 1.0)},
	"pemberton": {"name": "Mr. Pemberton", "kind": "customer", "color": Color(0.75, 0.7, 0.95),
		"address_seed": 7,
		"first": "Mr. Pemberton here. I order from these apps daily and have been disappointed daily. Prove me wrong.",
		"on_time": ["\"Hm. Still warm. Adequate.\" Mr. Pemberton tipped an extra $%d.",
			"\"You didn't ring the doorbell eleven times. Remarkable.\" +$%d from Mr. Pemberton.",
			"\"I suppose I'll order again tomorrow.\" Mr. Pemberton added $%d."],
		"late": ["\"I aged a full year waiting for this.\" Mr. Pemberton is not tipping extra.",
			"\"My soup has achieved room temperature.\" Mr. Pemberton sighs at you through the window."],
		"bonus": 5},
	"darnell": {"name": "Darnell", "kind": "rider",
		"color": Color(0.5, 0.95, 0.65),
		"first": "Darnell, night-shift nurse, hops in. \"You're new! I ride with this app every day. Same seat, same playlist.\"",
		"on_time": ["Darnell: \"Twelve-hour shift tonight. Thanks for the smooth ride.\" (+$%d tip)",
			"Darnell: \"You're my favorite driver. Don't tell the others.\" (+$%d tip)",
			"Darnell: \"Saw your Punta and almost cancelled. Glad I didn't.\" (+$%d tip)"],
		"late": ["Darnell: \"Charge nurse is gonna kill me. You're lucky I like you.\""],
		"bonus": 4},
}
const NPC_CHANCE := 0.14      # chance an offer comes from a regular (once you've met them)

# --- Cousin Ray's IOU -------------------------------------------------------------------
const RAY_DEBT := 1200.0
const RAY_PAYMENTS := [50.0, 100.0, 250.0]
## Ray checks in when you haven't sent anything for this many days.
const RAY_NAG_DAYS := 5

# --- Milestones -----------------------------------------------------------------------
# In order. Each one's check lives in Story._milestone_done(id). reward is cash paid when
# it's reached (from whoever says the line), 0 for none.
const MILESTONES := [
	{"id": "first_gig", "title": "Clock in", "goal": "Finish your first gig on any app.",
		"from": "mari", "text": "Saw you finish your first gig! Pro tip: peak hours pay more. Every app shows them on its home screen.", "reward": 0.0},
	{"id": "gas_money", "title": "Gas money", "goal": "Earn $250 from gigs.",
		"from": "mom", "text": "Your cousin says you're working hard. I'm proud of you, sweetheart. Eat a vegetable. Here's a little something.", "reward": 25.0},
	{"id": "oil", "title": "Treat the Punta", "goal": "Get an oil change at Lube & Tube.",
		"from": "ray", "text": "You changed the OIL?? Nobody's done that since 2009. She's gonna outlive us all.", "reward": 0.0},
	{"id": "rent", "title": "Make rent", "goal": "Pay a month's rent.",
		"from": "dottie", "text": "Rent received, hon. You're my favorite tenant. Don't tell the guy in room 3.", "reward": 0.0},
	{"id": "pay_ray", "title": "Pay off the car", "goal": "Pay Cousin Ray back the $1,200 for the Punta (Hustle Hub app).",
		"from": "ray", "text": "PAID IN FULL?! The Punta is officially yours. I'd say treat her well but honestly just keep her moving.", "reward": 0.0},
	{"id": "new_car", "title": "Upgrade your ride", "goal": "Get a 2011 or newer car (Honest Al's or DriveThyme). Rideshare apps open up.",
		"from": "mari", "text": "New ride! Now you can do Yoober and Drift too. Airport runs at night are where the money is.", "reward": 0.0},
	{"id": "move_out", "title": "Move out of the rented room", "goal": "Sign a lease on your own apartment.",
		"from": "dottie", "text": "Your own place! I'll miss you, hon. Here's a little housewarming money. Visit for pie.", "reward": 100.0},
	{"id": "own_car", "title": "Free and clear", "goal": "Own a better car outright: no loan, and Ray's paid off.",
		"from": "mom", "text": "No debts at all? Your father never managed that. Neither did I, honestly. Look at you.", "reward": 0.0},
	{"id": "five_figures", "title": "Five figures", "goal": "Earn $10,000 from gigs.",
		"from": "mari", "text": "Ten grand. You're officially a lifer. Welcome to the club, we meet in the DoorDish lot at 2 AM.", "reward": 0.0},
	{"id": "dream_house", "title": "The house with a yard", "goal": "Move into the house in Brandywine Hills.",
		"from": "mom", "text": "A HOUSE? With a yard? I'm coming for Thanksgiving. Don't argue. I'm so proud of you.", "reward": 0.0},
]

# --- Timed story texts -------------------------------------------------------------------
# [day, hour, from, text]: arrive once, at or after that time.
const BEATS := [
	[1, 7, "mom", "Good luck on your first day out there! Call me. Text me. Send a pigeon. Anything."],
	[1, 8, "ray", "Hey cuz. Enjoy the Punta. Don't forget the $1,200, no rush. (Rush a little.) Send it through the Hustle Hub app."],
	[1, 12, "dottie", "Welcome to the house, hon! Kitchen closes at 10, fridge is yours, toilet handle sticks. Rent's due end of the month."],
	[2, 9, "mari", "Hey! I'm Mari, I saw your Punta in the DoorDish lot. Nobody parks THAT badly unless they're new. Text me if you need tips."],
	[3, 18, "mari", "Rain and snow mean bonus pay on the delivery apps. Bad roads though. Your tires look like racing slicks, in a bad way."],
	[5, 10, "mom", "Did you eat today? Real food. Gas station hot dogs don't count."],
	[6, 20, "mari", "Jungle Flex blocks are steady money if you hate surprises. Reserve them in the app a couple hours before."],
	[9, 11, "mari", "Daily challenges in the Hustle Hub reset at midnight. Free money if you plan your day around them."],
	[14, 9, "mom", "Halfway through your first month! Whatever happens, you can always come home. But I know you won't need to."],
]

# --- Challenges -------------------------------------------------------------------------
# type decides what counts (see Story._count). n is picked from the range, reward scales.
const DAILY := [
	{"type": "jobs", "title": "Busy bee", "text": "Complete %d gigs", "n": [3, 5], "reward_per": 6.0},
	{"type": "app_jobs", "title": "App loyalty", "text": "Complete %d %s gigs", "n": [2, 3], "reward_per": 8.0},
	{"type": "earn", "title": "Make bank", "text": "Earn $%d from gigs", "n": [120, 200], "reward_per": 0.12},
	{"type": "peak", "title": "Rush hour", "text": "Finish %d gigs during peak hours", "n": [2, 3], "reward_per": 9.0},
	{"type": "on_time", "title": "Punctual", "text": "Finish %d gigs on time", "n": [3, 4], "reward_per": 6.0},
	{"type": "five_star", "title": "Five stars", "text": "Get %d five-star ratings", "n": [2, 4], "reward_per": 7.0},
	{"type": "miles", "title": "Road warrior", "text": "Drive %d miles", "n": [12, 25], "reward_per": 1.0},
	{"type": "apps", "title": "Multi-apper", "text": "Work on %d different apps", "n": [2, 2], "reward_per": 10.0},
	{"type": "weather", "title": "Neither rain nor snow", "text": "Finish %d gigs in bad weather", "n": [1, 2], "reward_per": 12.0},
]
const WEEKLY := [
	{"type": "jobs", "title": "Grinder", "text": "Complete %d gigs this week", "n": [18, 25], "reward_per": 4.0},
	{"type": "earn", "title": "Payday", "text": "Earn $%d from gigs this week", "n": [800, 1200], "reward_per": 0.08},
	{"type": "five_star", "title": "Fan favorite", "text": "Get %d five-star ratings this week", "n": [10, 14], "reward_per": 5.0},
	{"type": "miles", "title": "Odometer roller", "text": "Drive %d miles this week", "n": [90, 140], "reward_per": 0.6},
	{"type": "regulars", "title": "Know your regulars", "text": "Serve your regulars %d times this week", "n": [2, 3], "reward_per": 15.0},
]
const DAILY_COUNT := 3
const WEEKLY_COUNT := 2
