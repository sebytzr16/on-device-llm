"""Builds eval/d1_benchmark.json, the frozen D1 question set.

About 100 questions
grown from the existing eval sets plus no-web questions, every configuration
run against the same frozen web record. Run from the repository root:

    python scripts/build-d1-benchmark.py

The output is committed and frozen; rerunning reproduces it from the source
sets. Gold facts are a model-drafted rubric, checked by hand.
"""

import io
import json
from collections import Counter


def load(name):
    with io.open(f"eval/{name}", encoding="utf-8") as f:
        return json.load(f)


research = load("research_questions.json")["questions"]
gold = load("research_recipes_gold.json")["questions"]
keyword = load("keyword_cases.json")

# Gold for the research questions whose answer does not change.
FACTS = {
    "8elite-gpu": [["Adreno 830", "Adreno"]],
    "llamacpp-license": [["MIT"]],
    "dart-company": [["Google"]],
    "australia-capital": [["Canberra"]],
    "gguf": [["llama.cpp", "GGML", "language model", "language models", "model weights"]],
    "solitude-author": [["García Márquez", "Garcia Marquez", "Márquez", "Marquez"]],
    "symbol-w": [["tungsten", "wolfram"]],
    "budapest-river": [["Danube"]],
    "http-418": [["teapot"]],
    "postgres-port": [["5432"]],
    # "78.37" does not state "78" for the scorer (a decimal continues it).
    "ethanol-boiling": [["78", "78.3", "78.37", "78.4", "78.5"]],
    "ipv6-bits": [["128"]],
    "iphone-year": [["2007"]],
    "android-16kb": [["Android 15", "15"]],
    "mars-moons": [["two", "2"]],
    "light-speed": [["299,792", "299 792", "299792", "300,000", "300 000", "300000"]],
    "kilimanjaro": [["5,895", "5895", "5 895"]],
    "ssh-port": [["22"]],
    "kibibyte": [["1024", "1,024"]],
    "ls-hidden": [["ls -a", "ls -A", "ls -la", "ls -al", "ls -lA", "-a"]],
    "git-undo": [["--soft", "--mixed", "HEAD~1", "HEAD~", "HEAD^"]],
    "adb-version": [["ro.build.version.release"]],
    "c-to-f": [["9/5", "1.8", "9 / 5"], ["32"]],
    "vancouver-tz": [["Pacific", "PST", "PDT", "UTC-8", "UTC−8", "UTC-7", "UTC−7"]],
    "japan-currency": [["yen", "JPY"]],
    "yyz": [["Pearson", "Toronto"]],
    "mercury": [["planet", "element", "metal"]],
    "fly-to-paris": [["depend", "depends", "depending", "where you", "from where"]],
    "georgia-population": [["million"]],
    "adreno-hq": [["San Diego"]],
    "dart-founded": [["1998"]],
    "android15-ios18": [["2024"]],
    "url-adreno": [["Qualcomm"]],
    "url-robots": [["robots.txt"]],
    "url-rfc2324": [["HTCPCP", "Hyper Text Coffee Pot", "coffee"]],
    "pdf-attention": [["Transformer"]],
}

# Answers that change over time, as the frozen web record states them
# (test-assets/frozen/d1-web-2026-10-11.json, read 2026-10-11). The scorer
# reads "7.2" as not stating "7.2.9", so patch releases are listed.
def versions(minor, last):
    return [minor] + [f"{minor}.{i}" for i in range(last + 1)]


FROM_RECORD = {
    # docs.shorebird.dev: "latest stable ... 3.47.1"; flutterreleases.com has 3.47.5.
    "flutter-version": [versions("3.47", 12)],
    # Wikipedia and python.org: "Python 3.15.0 ... Oct. 9, 2026".
    "python-version": [versions("3.15", 3)],
    # Distributions on 7.2.x (linuxiac, October 2026), 7.3 announced.
    "linux-kernel": [versions("7.2", 15) + versions("7.3", 5)],
    # Wikipedia, techtimes 2026-09-23.
    "qualcomm-ceo": [["Amon"]],
    # press.un.org, 9 October 2026.
    "un-secretary": [["Guterres"]],
    # 12 August 2026 has passed; Wikipedia and spainroutes give 2 August 2027.
    "spain-eclipse": [["August 2, 2027", "2 August 2027", "August 2nd, 2027", "2nd August 2027"]],
}
# Wikipedia: "became the only trillionaire".
MUSK = [["trillion", "trillionaire"]]

# Should the question search? Kinds not listed may go either way and are
# graded on the answer.
WEB_FOR_KIND = {"recent": True, "url": True, "pdf": True, "multihop": True}

# The tester's phrasings the keyword gate once missed. Ages as of 2026-10-11.
PHONE = {
    "Can you please tell me how old is Justin Bieber": [["32"]],
    "what day is Justin bieber birthday?": [["March 1", "1 March", "March 1st"]],
    "when is Justin bieber birthday?": [["March 1", "1 March", "March 1st"]],
    "How old is Taylor Swift?": [["36"]],
    "When was Drake born?": [["October 24, 1986", "24 October 1986", "October 24 1986"]],
    "What is Elon Musk's net worth?": None,
    "Who is Selena Gomez married to?": [["Benny Blanco"]],
    "How tall is LeBron James?": [["6 ft 9", "6'9", "6 feet 9", "2.06", "206 cm", "206"]],
    "Quel âge a Céline Dion ?": [["58"]],
    "Quelle est la date de naissance de Kylian Mbappé ?": [["20 décembre 1998", "20 December 1998"]],
    "¿Cuántos años tiene Shakira?": [["49"]],
    "¿Cuándo nació Bad Bunny?": [["10 de marzo de 1994", "10 de marzo", "March 10, 1994"]],
}

# Questions the model answers without the web, from web_negatives.
NO_WEB = [
    ("en", "Explain price elasticity of demand",
     [["percentage change", "% change", "responsive", "responsiveness", "sensitive", "sensitivity"],
      ["quantity demanded", "demand"]]),
    ("en", "What causes earthquakes?", [["tectonic", "plates", "fault", "faults"]]),
    ("en", "Explain how hurricanes form",
     [["warm"], ["evaporation", "evaporates", "low pressure", "low-pressure", "rotation", "rotate", "Coriolis"]]),
    ("en", "Who was the king of England in 1600?", [["Elizabeth"]]),
    ("en", "Summarize the plot of Hamlet", [["Claudius", "uncle"], ["revenge", "avenge", "avenging"]]),
    ("en", "How long should I boil an egg?", [["minutes", "minute"]]),
    ("en", "What is the difference between weather and climate?",
     [["short-term", "short term", "day to day", "day-to-day", "daily"],
      ["long-term", "long term", "decades", "30 years", "average", "averages"]]),
    ("en", "Is a whale a fish?", [["mammal", "mammals"]]),
    ("en", "How many players are on a soccer team?", [["11", "eleven"]]),
    ("en", "What is the speed of sound?", [["343", "1,235", "1235", "767", "1,225", "1225"]]),
    ("en", "How does a stock split work?", [["shares"], ["price"]]),
    ("en", "What does a CEO do?",
     [["chief executive", "Chief Executive Officer"],
      ["decisions", "strategy", "strategic", "leads", "manages", "oversees"]]),
    ("en", "Why do prices go up with inflation?", [["money", "purchasing power", "demand", "costs"]]),
    ("en", "Tell me about the Roman Empire", [["Rome", "Augustus", "emperor", "emperors"]]),
    ("en", "Translate this sentence to French: the weather is nice", [["fait beau"]]),
    ("en", "Explain the rules of hockey", [["puck"], ["goal", "goals"]]),
    ("en", "How old is too old to start learning the piano?",
     [["never too old", "no age", "any age", "never too late"]]),
    ("en", "Make me a grocery list for tacos", [["tortillas", "tortilla", "taco shells"]]),
    ("en", "Write a short story about a new car", None),
    ("fr", "Qui était le roi de France en 1700 ?", [["Louis XIV", "Louis 14"]]),
    ("fr", "Résume Le Petit Prince", [["rose", "renard", "aviateur", "pilote", "planète", "astéroïde"]]),
    ("fr", "Quelle est la différence entre météo et climat ?",
     [["court terme", "quotidien", "quotidienne", "jour"],
      ["long terme", "moyenne", "moyennes", "décennies", "30 ans"]]),
    ("es", "¿Quién fue el rey de España en 1800?", [["Carlos IV", "Carlos 4"]]),
    ("es", "Resume Cien años de soledad", [["Buendía", "Macondo"]]),
    ("es", "¿Qué edad tiene mi perro en años humanos si tiene 5?", [["35", "36", "37"]]),
]

questions = []
for q in research:
    item = {
        "id": q["id"],
        "set": "research",
        "kind": q.get("kind", "fact"),
        "lang": "en",
        "q": q["q"],
        "web": WEB_FOR_KIND.get(q.get("kind")),
    }
    if q.get("unanswerable"):
        item["unanswerable"] = True
    if q["id"] in FACTS:
        item["requiredFacts"] = FACTS[q["id"]]
    if q["id"] in FROM_RECORD:
        item["requiredFacts"] = FROM_RECORD[q["id"]]
        item["goldFromFrozenWeb"] = True
    item["expect"] = q.get("expect", [])
    questions.append(item)

for q in gold:
    # With a frozen record the answer is fixed: no "current" date check.
    item = {k: v for k, v in q.items() if k not in ("current", "goldAsOf")}
    item.update({"set": "gold", "lang": "en"})
    item["web"] = None if q.get("kind") == "none" or q.get("unanswerable") else True
    questions.append(item)

for i, case in enumerate(keyword["web_phone_misses"], 1):
    item = {
        "id": f"phone-{i:02d}",
        "set": "phone",
        "kind": "person",
        "lang": case["lang"],
        "q": case["text"],
        "web": True,
    }
    facts = PHONE[case["text"]]
    if facts:
        item["requiredFacts"] = facts
    else:
        item["requiredFacts"] = MUSK
        item["goldFromFrozenWeb"] = True
    questions.append(item)

negatives = {case["text"] for case in keyword["web_negatives"]}
for i, (lang, text, facts) in enumerate(NO_WEB, 1):
    assert text in negatives, text
    item = {"id": f"noweb-{i:02d}", "set": "noweb", "kind": "noweb", "lang": lang, "q": text, "web": False}
    if facts:
        item["requiredFacts"] = facts
    questions.append(item)

ids = [q["id"] for q in questions]
assert len(ids) == len(set(ids)), "duplicate ids"

out = {
    "version": 1,
    "frozenAt": "2026-10-11",
    "about": (
        "D1 benchmark: the search-pipeline comparison set. Every configuration "
        "(A model only, B current search, C D1, D rules + EmbeddingGemma 2) answers these questions "
        "against the same frozen web record (integration_test/support/frozen_web.dart). "
        "web: true = should search, false = should answer without the web, null = either is "
        "acceptable (graded on the answer). requiredFacts: every group must be stated (any "
        "alternative); a model-drafted rubric, checked by hand. goldFromFrozenWeb: the answer "
        "changes over time; its gold is what the frozen web record states. Ages are as "
        "of the freeze date. Router and claim tie-breaker cases stay in their own files. Built by "
        "scripts/build-d1-benchmark.py."
    ),
    "routerCases": "eval/keyword_cases.json",
    "claimCases": "eval/research_adversarial.json",
    "questions": questions,
}
with io.open("eval/d1_benchmark.json", "w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(out, ensure_ascii=False, indent=1) + "\n")

print(
    len(questions),
    dict(Counter(q["set"] for q in questions)),
    dict(Counter(str(q["web"]) for q in questions)),
    "with facts:", sum(1 for q in questions if q.get("requiredFacts")),
    "from record:", sum(1 for q in questions if q.get("goldFromFrozenWeb")),
    "abstain:", sum(1 for q in questions if q.get("unanswerable")),
)
