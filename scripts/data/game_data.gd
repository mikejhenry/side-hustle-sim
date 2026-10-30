class_name GameData
extends RefCounted
## All tunable numbers live here so balancing the game is one-file work.
## Brand names are parodies made up for this game.

# --- Time -------------------------------------------------------------------
const REAL_SECONDS_PER_GAME_MINUTE := 2.0   # 1 game day = 48 real minutes
const START_HOUR := 7
const BILL_CYCLE_DAYS := 30                 # rent, phone, insurance (and car loans) are due monthly
const BILL_HOUR := 9                        # bills auto-pay at 9:00 AM on the due day
const LATE_FEE := 50.0
const EVICTION_GRACE_DAYS := 5              # rent this many days overdue = evicted
const REPO_GRACE_DAYS := 5                  # car loan this many days overdue = repossessed
const TICKET_DUE_DAYS := 7                  # unpaid tickets become a bill due in a week
const DAY_NAMES := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

# --- Money & world scale ------------------------------------------------------
const START_MONEY := 140.0
const METERS_PER_MILE := 160.0              # the town is compressed: 160 m feels like a mile
const GAS_PRICE := 3.49
const GAME_YEAR := 2026

# --- Needs (per game minute) -------------------------------------------------
const HUNGER_DRAIN := 0.10       # 100 -> 0 in ~17 game hours
const BLADDER_FILL := 0.20       # 0 -> 100 in ~8 game hours
const ENERGY_DRAIN := 0.065      # awake ~25 game hours before collapsing
const SLEEP_GAIN := 0.21         # 8 hours of decent sleep refills energy
const STARVING_ENERGY_MULT := 2.5
const BLADDER_ACCIDENT_COST := 30.0

# --- Phone --------------------------------------------------------------------
const PHONE_DRAIN_ONLINE := 0.12
const PHONE_DRAIN_IDLE := 0.03
const PHONE_CHARGE := 0.8        # while in the car or sleeping at home

# --- Car wear (per game mile) ------------------------------------------------
const OIL_PER_MILE := 0.45       # % oil life used per mile
const TIRE_PER_MILE := 0.12      # % tread used per mile
const ENGINE_DAMAGE_NO_OIL := 1.5
const OIL_CHANGE_PRICE := 39.0
const ENGINE_REPAIR_PER_PCT := 9.0
const TOW_PRICE := 85.0

# --- Cars --------------------------------------------------------------------
# engine: force per driven wheel. top_speed: m/s. tank: gallons.
# comfort scales rideshare pay and ratings. insurance: per month.
const CARS := {
	"rustwagon": {
		"name": "1995 Fiot Punta GT", "year": 1995, "price": 0, "trade_in": 250,
		"engine": 2550.0, "top_speed": 27.0, "mpg": 20.0, "tank": 12.0,
		"comfort": 0.7, "insurance": 150.0, "tires": 180.0,
		"color": Color(0.52, 0.36, 0.26), "size": Vector3(1.66, 0.75, 3.76), "odometer": 187412.0,
		# 3D model: "(FREE) 1995 Fiat Punto GT" by Karol Miklas, CC-BY-4.0 (credits in README.md).
		"model": "res://assets/cars/free_1995_fiat_punto_gt/scene.gltf", "model_length": 3.76,
		# Where the driver's eyes and the model's mirrors are (x is the driver's side).
		"eye": Vector3(0.36, 1.15, -0.3), "rearview": Vector3(0.0, 1.26, 0.13),
		"side_mirror": Vector3(0.85, 0.935, 0.462), "side_mirror_size": Vector2(0.12, 0.085),
	},
	"civil": {
		"name": "2013 Hondo Civil", "year": 2013, "price": 1400, "trade_in": 700,
		"engine": 3050.0, "top_speed": 33.0, "mpg": 31.0, "tank": 13.0,
		"comfort": 1.0, "insurance": 190.0, "tires": 220.0,
		"color": Color(0.75, 0.77, 0.8), "size": Vector3(1.8, 0.72, 4.4), "odometer": 121300.0,
	},
	"pious": {
		"name": "2018 Toyoyo Pious Hybrid", "year": 2018, "price": 4200, "trade_in": 2000,
		"engine": 3250.0, "top_speed": 34.0, "mpg": 52.0, "tank": 11.0,
		"comfort": 1.1, "insurance": 220.0, "tires": 260.0,
		"color": Color(0.2, 0.45, 0.8), "size": Vector3(1.8, 0.75, 4.5), "odometer": 78400.0,
	},
	"passit": {
		"name": "2021 Folkswagon Passit", "year": 2021, "price": 9500, "trade_in": 4800,
		"engine": 4100.0, "top_speed": 40.0, "mpg": 34.0, "tank": 15.0,
		"comfort": 1.3, "insurance": 270.0, "tires": 340.0,
		"color": Color(0.1, 0.1, 0.12), "size": Vector3(1.9, 0.78, 4.8), "odometer": 31000.0,
	},
	"voltz": {
		"name": "2025 Voltz Model Tree EV", "year": 2025, "price": 21000, "trade_in": 12000,
		"engine": 5400.0, "top_speed": 48.0, "mpg": 120.0, "tank": 10.0,
		"comfort": 1.6, "insurance": 360.0, "tires": 480.0,
		"color": Color(0.85, 0.12, 0.12), "size": Vector3(1.9, 0.7, 4.7), "odometer": 900.0,
	},
}
const CAR_ORDER := ["rustwagon", "civil", "pious", "passit", "voltz"]

# --- Housing ------------------------------------------------------------------
const HOMES := {
	"room": {"name": "Rented room at Dottie's Boarding House", "short": "Dottie's room",
		"rent": 950.0, "deposit": 0.0, "sleep_quality": 0.8},
	"studio": {"name": "Studio at Maple Court Apartments", "short": "Maple Court studio",
		"rent": 1500.0, "deposit": 450.0, "sleep_quality": 1.0},
	"twobr": {"name": "2-bed apartment at Lakeview Towers", "short": "Lakeview 2BR",
		"rent": 2400.0, "deposit": 1200.0, "sleep_quality": 1.15},
	"house": {"name": "3-bed house in Brandywine Hills", "short": "Brandywine house",
		"rent": 3900.0, "deposit": 7500.0, "sleep_quality": 1.3},
}
const HOME_ORDER := ["room", "studio", "twobr", "house"]
const PHONE_BILL := 85.0
const PHONE_PRO_NAME := "Pear uPhone 16 Pro"
const PHONE_PRO_PRICE := 350.0

# Financing (DriveThyme Auto Finance). Same cars as Honest Al's, marked up, with a down
# payment and a 12-month loan at a high rate: easier to get into, costs more in the end.
const FINANCE_NAME := "DriveThyme Auto Finance"
const FINANCE_MARKUP := 1.15
const FINANCE_DOWN := 0.15
const FINANCE_APR := 0.239
const FINANCE_MONTHS := 12

# Traffic law
const SPEED_LIMIT := 30.0       # mph in town
const BELTWAY_LIMIT := 45.0     # mph on the ring road
const TICKET_SLACK := 7.0       # mph over the limit before a cop bothers
const TICKET_BASE := 75.0
const TICKET_PER_MPH := 10.0
const EVADING_FINE := 150.0
const RECKLESS_FINE := 180.0
const RED_LIGHT_FINE := 150.0
const HOME_GROCERIES_PRICE := 32.0
const HOME_GROCERIES_MEALS := 6

# --- Gig apps -------------------------------------------------------------------
# peaks: [start_hour, end_hour, demand multiplier]
const APPS := {
	"yoober": {
		"name": "Yoober", "kind": "ride", "color": Color(0.08, 0.08, 0.08), "accent": Color(1, 1, 1),
		"tagline": "Strangers in your car. For money.",
		"peaks": [[7, 9, 1.6], [16, 19, 1.8], [22, 24, 1.5], [0, 2, 1.9]],
		"base": 2.5, "per_mile": 1.15, "min_year": 2011,
	},
	"drift": {
		"name": "Drift", "kind": "ride", "color": Color(0.95, 0.15, 0.55), "accent": Color(1, 1, 1),
		"tagline": "Ride with a buddy you'll never see again.",
		"peaks": [[6, 9, 1.5], [17, 20, 1.7], [23, 24, 1.6], [0, 3, 1.6]],
		"base": 2.2, "per_mile": 1.25, "min_year": 2011,
	},
	"doordish": {
		"name": "DoorDish", "kind": "food", "color": Color(0.92, 0.2, 0.15), "accent": Color(1, 1, 1),
		"tagline": "Cold fries, delivered warm-ish.",
		"peaks": [[11, 14, 1.6], [17, 21, 1.9]],
		"base": 2.5, "per_mile": 0.7,
	},
	"instacrate": {
		"name": "Instacrate", "kind": "grocery", "color": Color(0.1, 0.62, 0.3), "accent": Color(1, 0.75, 0.2),
		"tagline": "We pick the bruised bananas so they don't have to.",
		"peaks": [[9, 12, 1.4], [15, 19, 1.6]],
		"base": 5.0, "per_mile": 0.55, "per_item": 0.45,
	},
	"jungleflex": {
		"name": "Jungle Flex", "kind": "flex", "color": Color(0.1, 0.35, 0.45), "accent": Color(1, 0.6, 0.1),
		"tagline": "Grab a block. Grab a box. Grab another box.",
		"peaks": [[6, 8, 1.3], [17, 19, 1.25]],
		"blocks": [6, 10, 14, 18], "block_minutes": 180, "block_pay": 54.0,
	},
}
const APP_ORDER := ["yoober", "drift", "doordish", "instacrate", "jungleflex"]
const OFFER_MINUTES := 12
const BASE_OFFER_CHANCE := 0.06   # per game minute while online and idle

# --- Food --------------------------------------------------------------------
# [label, price, hunger restored, energy]
const RESTAURANTS := {
	"Burger Barn": [["Barn Burger combo", 9.49, 55.0, 0.0], ["Kids meal (no shame)", 5.99, 30.0, 0.0]],
	"Taco Loco": [["3 street tacos", 7.25, 40.0, 0.0], ["Burrito the size of a cat", 10.50, 65.0, 0.0]],
	"Wok This Way": [["Orange chicken bowl", 9.95, 55.0, 0.0], ["Egg rolls (2)", 3.95, 18.0, 0.0]],
	"Grotty Pizza": [["Two boardwalk slices + soda", 6.50, 40.0, 3.0], ["Whole pie", 15.00, 90.0, 0.0]],
	"Capritoni's": [["The Bobbie (Thanksgiving sub)", 11.50, 70.0, 0.0], ["Half cheesesteak", 7.25, 40.0, 0.0]],
	"Sunny Side Diner": [["Lumberjack breakfast", 11.25, 70.0, 5.0], ["Coffee (bottomless)", 2.50, 0.0, 15.0]],
	"Cluckin' Good": [["3pc chicken meal", 10.25, 60.0, 0.0], ["Sweet tea", 1.99, 2.0, 6.0]],
	"Bean Scene Coffee": [["Large drip coffee", 3.25, 0.0, 18.0], ["Breakfast sandwich", 5.75, 30.0, 4.0]],
	"Noodle Nirvana": [["Spicy ramen", 12.00, 60.0, 0.0], ["Gyoza (6)", 6.00, 25.0, 0.0]],
	# Route 40 strip (Churchmans Loop)
	"McDougal's": [["Big Mick meal", 9.29, 60.0, 0.0], ["McNuggies (10)", 5.49, 35.0, 0.0]],
	"Burger Monarch": [["Whopping meal", 9.99, 62.0, 0.0], ["Onion rings", 3.29, 15.0, 0.0]],
	"Chick-Fil-Hey": [["Chicken sandwich meal", 10.19, 60.0, 0.0], ["Waffle fries", 3.05, 18.0, 0.0]],
	"Wendell's": [["Baconeater combo", 10.49, 62.0, 0.0], ["Frosty-ish", 2.49, 10.0, 0.0]],
	"Pizza Hutch": [["Personal pan pizza", 7.99, 45.0, 0.0], ["Large pepperoni", 16.99, 95.0, 0.0]],
	"Taco Bellhop": [["Crunchwrap Supremo", 5.49, 35.0, 0.0], ["Nacho fries", 2.29, 12.0, 0.0]],
	"Domino Effect Pizza": [["Medium two-topping", 11.99, 70.0, 0.0], ["Lava cake", 4.99, 15.0, 0.0]],
	"Five Dudes Burgers": [["Cheeseburger + fries", 15.99, 75.0, 0.0], ["Cajun fries", 5.99, 22.0, 0.0]],
	"Pop-Eyed Chicken": [["Spicy chicken sandwich", 5.99, 40.0, 0.0], ["3pc tenders + biscuit", 8.49, 50.0, 0.0]],
	"Sub Way Out": [["Footlong whatever", 9.99, 55.0, 0.0], ["Cookie", 1.29, 6.0, 0.0]],
}
const GAS_STATION_MENU := [
	["Gas station hot dog", 2.99, 22.0, 0.0],
	["Bag of chips", 1.99, 10.0, 0.0],
	["Coffee", 1.79, 0.0, 12.0],
	["Mega Jolt energy drink", 3.49, 0.0, 25.0],
]

const GROCERY_ITEMS := [
	"Milk", "Eggs", "Bread", "Bananas", "Apples", "Cereal", "Chicken", "Rice",
	"Pasta", "Coffee Beans", "Paper Towels", "Dog Food", "Ice Cream", "Chips",
	"Soda 12-pack", "Cheese", "Yogurt", "Tomatoes",
]

const FIRST_NAMES := [
	"Ashley", "Brandon", "Carla", "Devon", "Erin", "Frank", "Gloria", "Hector", "Imani",
	"Jake", "Kayla", "Luis", "Monique", "Nate", "Olivia", "Priya", "Quinn", "Rosa",
	"Steve", "Tasha", "Uma", "Victor", "Wendy", "Xavier", "Yolanda", "Zeke",
]
