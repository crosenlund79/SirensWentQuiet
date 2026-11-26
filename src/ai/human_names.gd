class_name HumanNames
extends RefCounted
## Experiment 012 (E), the user's §12: every ordinary humanoid psycho (the
## psycho, the runner, the brute and the bomber) was somebody, with a first
## and a last name from large pools: Thomas Whitaker, Helen Crawford, Walter
## Briggs, Margaret Ellis. A plausible North-American / Northern-European mix
## for a cold northern town. No secret story identities, and the Architect is
## never an AIEnemy, so he never gets one here.
##
## The name depends only on the appearance seed (AIEnemy.appearance) and the
## look's sex (HumanoidLooks.look(kind, seed).body.sex, 0 male .. 1 female),
## so it persists through saves wherever the seed does (POI encounters save
## it as "app", corpses as "app" and "name").
##
## No duplicates within one encounter: unique_seed() steps the seed by a
## multiple of the archetype's variety, which keeps the same look (look index
## = seed mod variety) but gives a different name.

const MALE := [
	"Thomas", "Walter", "Harold", "George", "Arthur", "Frank", "Edward", "Henry", "Albert", "Raymond",
	"Eugene", "Howard", "Leonard", "Gerald", "Ronald", "Donald", "Kenneth", "Dennis", "Gary", "Larry",
	"Wayne", "Roger", "Douglas", "Glenn", "Dale", "Craig", "Keith", "Bruce", "Neil", "Stuart",
	"Graham", "Malcolm", "Duncan", "Gordon", "Ian", "Alan", "Colin", "Derek", "Trevor", "Clive",
	"Martin", "Peter", "Paul", "Mark", "Michael", "David", "Daniel", "Matthew", "Andrew", "James",
	"John", "Robert", "William", "Richard", "Charles", "Joseph", "Christopher", "Steven", "Brian", "Kevin",
	"Jason", "Jeffrey", "Scott", "Eric", "Gregory", "Timothy", "Patrick", "Sean", "Brendan", "Liam",
	"Owen", "Connor", "Ryan", "Tyler", "Kyle", "Brandon", "Justin", "Travis", "Cody", "Dustin",
	"Shane", "Wade", "Clay", "Hank", "Earl", "Vernon", "Floyd", "Lloyd", "Chester", "Marvin",
	"Calvin", "Curtis", "Russell", "Warren", "Stanley", "Norman", "Herbert", "Clifford", "Gilbert", "Lester",
	"Erik", "Lars", "Nils", "Sven", "Anders", "Johan", "Mikael", "Henrik", "Jens", "Magnus",
	"Gunnar", "Bjorn", "Olaf", "Leif", "Torsten", "Ingvar", "Karl", "Axel", "Emil", "Oskar",
	"Viktor", "Fredrik", "Stefan", "Tobias", "Jonas", "Mats", "Pekka", "Jari", "Mikko", "Aleksi",
	"Elliot", "Nathan", "Adam", "Samuel", "Benjamin", "Jacob", "Lucas", "Noah", "Ethan", "Caleb",
	"Isaac", "Simon", "Victor", "Frederick", "Roy", "Ray", "Carl", "Glen", "Dean", "Jack",
	"Joe", "Bill", "Ted", "Fred", "Hugh", "Rex", "Wesley", "Mitchell", "Grant", "Murray",
]

const FEMALE := [
	"Helen", "Margaret", "Dorothy", "Ruth", "Evelyn", "Mildred", "Frances", "Irene", "Gladys", "Edna",
	"Shirley", "Barbara", "Joan", "Carol", "Judith", "Sandra", "Sharon", "Linda", "Donna", "Brenda",
	"Diane", "Janet", "Cheryl", "Debra", "Pamela", "Karen", "Susan", "Nancy", "Patricia", "Deborah",
	"Elaine", "Marilyn", "Beverly", "Lorraine", "Gail", "Wendy", "Denise", "Teresa", "Theresa", "Rita",
	"Jean", "Joyce", "Ann", "Anne", "Mary", "Elizabeth", "Catherine", "Christine", "Caroline", "Rebecca",
	"Rachel", "Sarah", "Laura", "Emily", "Jessica", "Jennifer", "Amanda", "Melissa", "Stephanie", "Nicole",
	"Heather", "Amy", "Angela", "Kimberly", "Lisa", "Michelle", "Tracy", "Dawn", "Tammy", "Crystal",
	"Kelly", "Erin", "Megan", "Kayla", "Ashley", "Brittany", "Courtney", "Lindsay", "Holly", "Tara",
	"Molly", "Hannah", "Abigail", "Grace", "Chloe", "Olivia", "Sophie", "Lucy", "Ella", "Claire",
	"Fiona", "Moira", "Isla", "Eileen", "Maureen", "Sheila", "Brenna", "Kathleen", "Colleen", "Bridget",
	"Ingrid", "Astrid", "Karin", "Kristin", "Sigrid", "Solveig", "Greta", "Liv", "Freja", "Linnea",
	"Maja", "Elin", "Annika", "Britt", "Hanna", "Ida", "Johanna", "Marit", "Tuula", "Aino",
	"Hilda", "Agnes", "Martha", "Edith", "Ethel", "Florence", "Louise", "Alice", "Rose", "Violet",
	"Vera", "Norma", "Lois", "Doris", "Bonnie", "Marjorie", "Peggy", "Connie", "Judy", "Kathy",
	"Paula", "Renee", "Yvonne", "Monica", "Vanessa", "Natalie", "Victoria", "Shannon", "Leah", "Naomi",
	"Joanne", "Lynn", "Sue", "Beth", "Jill", "Kate", "Meg", "Nora", "Ruby", "June",
]

const SURNAMES := [
	"Whitaker", "Crawford", "Briggs", "Ellis", "Thompson", "Anderson", "Johnson", "Peterson", "Hansen", "Larson",
	"Nielsen", "Olsen", "Carlson", "Swanson", "Lindqvist", "Lindgren", "Nordin", "Holm", "Berg", "Dahl",
	"Lund", "Strand", "Sandberg", "Ekholm", "Bergstrom", "Halvorsen", "Johansen", "Eriksen", "Kowalski", "Novak",
	"Mackenzie", "MacLeod", "Campbell", "Fraser", "Murray", "Duncan", "Ferguson", "Robertson", "Stewart", "Graham",
	"Gallagher", "Brennan", "Doyle", "Kelly", "Walsh", "Sullivan", "O'Connor", "Fitzgerald", "Donnelly", "Quinn",
	"Harper", "Fletcher", "Cooper", "Turner", "Baker", "Carter", "Mason", "Fisher", "Walker", "Hunter",
	"Parker", "Porter", "Sawyer", "Tanner", "Wheeler", "Chandler", "Spencer", "Webster", "Collier", "Thatcher",
	"Bishop", "Abbott", "Prescott", "Whitmore", "Ashford", "Bradley", "Barlow", "Crowley", "Dawson", "Emerson",
	"Garrett", "Hadley", "Hollis", "Kendall", "Lawson", "Marsh", "Norris", "Pratt", "Reeves", "Sutton",
	"Talbot", "Underwood", "Vaughn", "Whitfield", "Yates", "Bennett", "Coleman", "Dixon", "Foster", "Gibson",
	"Hayes", "Jennings", "Knight", "Lambert", "Moore", "Nash", "Owens", "Palmer", "Reynolds", "Shaw",
	"Tucker", "Wallace", "Warren", "Wells", "Young", "Burke", "Caldwell", "Dunn", "Ford", "Gray",
	"Holt", "Ingram", "Jensen", "Kirby", "Lowe", "Mercer", "Nolan", "Osborne", "Pearson", "Rhodes",
	"Saunders", "Toomey", "Upton", "Vance", "Wilder", "Ackerman", "Becker", "Dietrich", "Engel", "Fischer",
	"Gruber", "Hoffman", "Keller", "Lehmann", "Muller", "Richter", "Schroeder", "Vogel", "Weber", "Zimmerman",
	"Virtanen", "Korhonen", "Nieminen", "Makinen", "Lehtonen", "Laine", "Heikkinen", "Salo", "Koskinen", "Rantanen",
	"Tremblay", "Gagnon", "Bouchard", "Gauthier", "Lavoie", "Pelletier", "Fortin", "Moreau", "Girard", "Leblanc",
	"Henderson", "McAllister", "Ramsay", "Sinclair", "Kerr", "Boyd", "Gillespie", "Mathers", "Pruitt", "Holloway",
]

const KIND_LABELS := {"psycho": "Psycho", "runner": "Runner", "brute": "Brute", "bomber": "Bomber"}
const UNIQUE_TRIES := 64


## A full name for appearance seed `seed` (deterministic).
static func for_seed(seed: int, female: bool) -> String:
	var firsts: Array = FEMALE if female else MALE
	var f: String = firsts[posmod(hash([seed, "first"]), firsts.size())]
	var s: String = SURNAMES[posmod(hash([seed, "last"]), SURNAMES.size())]
	return "%s %s" % [f, s]


## Female by the look's body (sex >= 0.5); kinds without a humanoid look by the seed.
static func is_female(kind: String, seed: int) -> bool:
	var l := HumanoidLooks.look(kind, seed)
	if l.is_empty():
		return posmod(hash([seed, "sex"]), 2) == 1
	var b: Variant = l.get("body", {})
	return typeof(b) == TYPE_DICTIONARY and float((b as Dictionary).get("sex", 0.0)) >= 0.5


## The name of an enemy of `kind` with appearance `seed` ("" for kinds that get none).
static func for_enemy(kind: String, seed: int) -> String:
	if not KIND_LABELS.has(kind):
		return ""
	return for_seed(seed, is_female(kind, seed))


static func kind_label(kind: String) -> String:
	return str(KIND_LABELS.get(kind, kind.capitalize()))


## A seed for `kind` near `seed` whose name is not in `taken` (names -> true,
## or an Array of names). Steps by a multiple of the archetype's variety, so
## the look stays the same; `seed` itself when it is free.
static func unique_seed(kind: String, seed: int, taken: Variant) -> int:
	var step := maxi(HumanoidLooks.variety(kind), 1) * 7
	for k in UNIQUE_TRIES:
		var s := seed + k * step
		var n := for_enemy(kind, s)
		if n == "" or not _has(taken, n):
			return s
	return seed


static func _has(taken: Variant, n: String) -> bool:
	if taken is Dictionary:
		return (taken as Dictionary).has(n)
	if taken is Array:
		return (taken as Array).has(n)
	return false


## The names in use in `roster`'s scene: its living enemies and the corpses
## (group Corpse.GROUP) lying there. names -> true.
static func taken_names(roster: Node) -> Dictionary:
	var out := {}
	if roster == null or not is_instance_valid(roster):
		return out
	var list: Variant = roster.get("enemies")
	if list is Array:
		for e in list:
			if is_instance_valid(e) and e is AIEnemy and (e as AIEnemy).alive and (e as AIEnemy).display_name != "":
				out[(e as AIEnemy).display_name] = true
	if roster.is_inside_tree():
		for c in roster.get_tree().get_nodes_in_group(Corpse.GROUP):
			var n: Variant = c.get("display_name")
			if n is String and n != "":
				out[n] = true
	return out
