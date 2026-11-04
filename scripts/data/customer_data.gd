class_name CustomerData
extends RefCounted
## Customer personalities, random job events and star rating rules for the gig apps.
## All balance numbers for ratings live here, next to the text the customers say.

# --- Personalities -------------------------------------------------------------------
# weight: how common they are. night_weight replaces it from 10 PM to 3 AM.
# tip: tip multiplier. stars: how many stars they knock off (or add) out of habit.
# crash_mult: how much they care about rough driving. hurry: scales the time they give you
# (under 1 = tighter deadline). on_time_tip: extra tip for being on time.
# rating: the range of the customer's own star rating shown on the offer.
const PERSONALITIES := {
	"friendly": {
		"label": "Friendly", "icon": "🙂", "weight": 30, "night_weight": 12,
		"tip": 1.0, "stars": 0.0, "crash_mult": 1.0, "hurry": 1.0, "on_time_tip": 0.0, "rating": [4.8, 5.0],
	},
	"chatty": {
		"label": "Chatty", "icon": "💬", "weight": 18, "night_weight": 12,
		"tip": 1.1, "stars": 0.0, "crash_mult": 1.0, "hurry": 1.0, "on_time_tip": 0.0, "rating": [4.7, 5.0],
	},
	"quiet": {
		"label": "Quiet", "icon": "🎧", "weight": 16, "night_weight": 8,
		"tip": 0.9, "stars": 0.0, "crash_mult": 1.0, "hurry": 1.0, "on_time_tip": 0.0, "rating": [4.7, 4.95],
	},
	"in_a_hurry": {
		"label": "In a hurry", "icon": "⏱", "weight": 14, "night_weight": 6,
		"tip": 1.0, "stars": 0.0, "crash_mult": 1.0, "hurry": 0.75, "on_time_tip": 4.0, "rating": [4.6, 4.95],
	},
	"picky": {
		"label": "Picky", "icon": "🧐", "weight": 10, "night_weight": 6,
		"tip": 0.9, "stars": -0.5, "crash_mult": 2.0, "hurry": 1.0, "on_time_tip": 0.0, "rating": [4.5, 4.9],
	},
	"rude": {
		"label": "Rude", "icon": "😠", "weight": 8, "night_weight": 12,
		"tip": 0.3, "stars": -1.0, "crash_mult": 1.5, "hurry": 0.9, "on_time_tip": 0.0, "rating": [3.9, 4.5],
	},
	"big_tipper": {
		"label": "Big tipper", "icon": "💰", "weight": 4, "night_weight": 4,
		"tip": 2.2, "stars": 0.5, "crash_mult": 1.0, "hurry": 1.0, "on_time_tip": 0.0, "rating": [4.9, 5.0],
	},
	"partying": {
		"label": "Partying", "icon": "🎉", "weight": 0, "night_weight": 40,
		"tip": 1.4, "stars": 0.0, "crash_mult": 0.7, "hurry": 1.0, "on_time_tip": 0.0, "rating": [4.4, 4.95],
	},
}
const NIGHT_START := 22
const NIGHT_END := 3
## Platinum drivers never get the worst customers, and see big tippers more often.
const PLATINUM_SKIP := ["rude"]
const PLATINUM_BOOST := {"big_tipper": 3.0, "friendly": 1.3}

# What they say. Rides use greet / chat / bye. Deliveries use note (on the order) and bye.
const LINES := {
	"friendly": {
		"greet": ["\"Hi! Thanks for grabbing me.\"", "\"Morning! Or is it afternoon? Who knows anymore.\""],
		"chat": ["\"Nice day for it, huh?\""],
		"bye": ["\"Thanks, have a good one!\"", "\"You're the best, drive safe.\""],
		"note": ["Thank you so much!! 😊", "Please knock, the doorbell is broken.", "Leave it by the door, thanks!"],
	},
	"chatty": {
		"greet": ["\"Oh good, a real person. So I've had the WILDEST week.\"", "\"Do you do this full time? What's that like?\""],
		"chat": [
			"\"...and that's when my cousin said the crypto would come back.\"",
			"\"Have you tried the new place on Market? The fries are life changing.\"",
			"\"I used to drive for Yoober too. Got deactivated for singing.\"",
			"\"Wait, do you know any good dentists around here?\"",
			"\"My landlord raised the rent AGAIN. Is yours bad too?\"",
			"\"So anyway, that's the third time this month the Wi-Fi went out.\"",
		],
		"bye": ["\"This was fun! Five stars, buddy.\"", "\"Okay I'll let you go. Bye! Bye. Okay bye!\""],
		"note": ["Hiii! Long day, I can't wait for this. You're a lifesaver 💕", "Please ring the bell, I'd love to say thanks in person!"],
	},
	"quiet": {
		"greet": ["They nod and put their earbuds in.", "\"Hey.\" They look out the window."],
		"chat": [],
		"bye": ["\"Thanks.\"", "A small wave and they're gone."],
		"note": ["Leave at door. No knock please.", "Don't ring the bell, baby is sleeping."],
	},
	"in_a_hurry": {
		"greet": ["\"Hi, I'm SO late. Can you go fast? Like, legally fast?\"", "\"Go go go, my flight boards in twenty minutes.\""],
		"chat": ["\"Is there a faster way? The GPS is wrong, take a left. No, a right.\"", "\"Are we almost there?\"", "They keep checking the time and sighing."],
		"bye": ["\"Okay thanks bye!\" They're already running.", "They jump out before you fully stop."],
		"note": ["PLEASE HURRY. Starving.", "Need this ASAP, meeting in 30 min!!"],
	},
	"picky": {
		"greet": ["\"Hi. Is the AC on? It feels warm in here.\"", "\"Could you not take Market Street? I hate Market Street.\""],
		"chat": ["\"You were a little close to that car back there.\"", "\"Hm. Interesting route.\""],
		"bye": ["\"It was fine.\"", "\"Your car smells a little like fries, just so you know.\""],
		"note": ["Hand it to me directly. Do NOT leave at door. Check the receipt.", "Make sure the drinks are UPRIGHT. Last driver ruined my latte."],
	},
	"rude": {
		"greet": ["They get in without a word and slam the door.", "\"Ugh, this car? Seriously?\""],
		"chat": ["\"Can you turn that garbage music off?\"", "\"Do you even know where you're going?\"", "They're on speakerphone, very loudly."],
		"bye": ["They get out without saying anything.", "\"Took you long enough.\""],
		"note": ["dont be late", "if its cold im reporting u"],
	},
	"big_tipper": {
		"greet": ["\"Hey friend! Long shift? I appreciate you guys.\""],
		"chat": ["\"I drove for Drift back in college. You guys don't get paid enough.\""],
		"bye": ["\"Here, a little extra for you. Get yourself something nice.\""],
		"note": ["Thank you for doing this, tip's on the way! 🙏"],
	},
	"partying": {
		"greet": ["\"WOOOO! Okay okay we're good. Can I plug my phone in?\"", "Three of them pile in, laughing at something you missed."],
		"chat": [
			"\"Turn it UP! This is my SONG!\"",
			"\"Do you know where we can get tacos right now? Like right now.\"",
			"\"Bro. Bro. You're my favorite driver ever.\"",
			"\"Wait, are we going the right way? Whatever, I trust you.\"",
		],
		"bye": ["\"Love you, driver! Five stars! Six stars!\"", "\"Thanks! Sorry about... everything.\""],
		"note": ["THE PARTY NEEDS SNACKS. hurry!!! 🎉", "we're in the back yard, follow the music"],
	},
}

# --- Random events -------------------------------------------------------------------------
# Chance that each event is planned for a job when you accept it.
const RIDE_SPILL_CHANCE := 0.08
const RIDE_SPILL_CHANCE_PARTY := 0.35
const RIDE_NEW_STOP_CHANCE := 0.10      # "can you actually drop me at..."
const RIDE_CANCEL_CHANCE := 0.06        # rider cancels while you're on the way
const WRONG_ADDRESS_CHANCE := 0.10      # food and grocery: the customer is somewhere else
const TIP_BAIT_CHANCE := 0.06           # the customer removes the tip after delivery (rude: 0.35)
const TIP_BAIT_CHANCE_RUDE := 0.35
const OUT_OF_STOCK_CHANCE := 0.30       # grocery: one item is out of stock
const DRINK_SPILL_ON_CRASH := 0.5       # food: a hard crash may spill the drink

const CLEANING_FEE := 20.0              # the rider is charged this and you get it...
const DETAILING_COST := 14.0            # ...but you pay for the seat shampoo right away
const RIDER_CANCEL_FEE := 3.75
const WRONG_ADDRESS_BONUS := 3.0

const SPILL_LINES := [
	"%s knocks a giant slushie all over your back seat.",
	"%s's iced coffee goes everywhere. \"Oh no. Oh nooo.\"",
	"A cup of something sticky tips over. %s: \"That was already there!\"",
]
const NEW_STOP_LINES := [
	"%s: \"Actually, can you drop me at %s instead? Sorry!\"",
	"%s: \"Change of plans, my friend is at %s now.\"",
]

# --- Star rating -----------------------------------------------------------------------------
## How much one rating moves your average (like averaging your last ~16 trips).
const RATING_WEIGHT := 0.06
const START_RATING := 4.8
const RANDOM_GRUMP_CHANCE := 0.04       # some people knock off a star for no reason
## [min rating, tier name, color, what it means]
const TIERS := [
	[4.85, "Platinum", Color(0.75, 0.9, 1.0), "Priority offers: +15% pay, and no rude customers."],
	[4.7, "Gold", Color(1.0, 0.82, 0.3), "Steady offers. 4.85 or better unlocks Platinum."],
	[4.5, "Silver", Color(0.8, 0.8, 0.85), "Fewer offers. Get back to 4.70 for Gold."],
	[0.0, "At risk", Color(1.0, 0.45, 0.35), "Few offers, and they pay 10% less. Below 4.30 you get deactivated."],
]
const PLATINUM_PAY := 1.15
const AT_RISK_PAY := 0.9
const WARN_BELOW := 4.5
const DEACTIVATE_BELOW := 4.3
const REACTIVATION_WAIT_DAYS := 1       # wait this long, then take the course
const REACTIVATION_FEE := 35.0          # "Driver Quality Course"
const REACTIVATED_RATING := 4.6
const RECENT_KEEP := 8                  # recent ratings shown in each app
