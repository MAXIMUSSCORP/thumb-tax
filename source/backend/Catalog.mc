// The single list of every earnable activity: label, detector, thresholds and exchange rate.
import Toybox.Lang;

module Catalog {
    var _all as Array<Dictionary>? = null;

    function e(id as Symbol, label as String, group as Symbol, detector as Symbol, unit as Symbol,
               rate as Float, verify as Symbol, cap as Number?, minSec as Number?, daily as Boolean,
               params as Dictionary) as Dictionary {
        return {:id => id, :label => label, :group => group, :detector => detector, :unit => unit,
                :rate => rate, :verify => verify, :cap => cap, :minSec => minSec, :daily => daily,
                :params => params};
    }

    function reps(low as Number, high as Number, minMs as Number, per as Number) as Dictionary {
        return {:low => low, :high => high, :minMs => minMs, :perDetect => per};
    }

    function hold(maxVar as Number, pose as Symbol) as Dictionary {
        return {:maxVar => maxVar, :pose => pose};
    }

    function active(hr as Number, v as Number) as Dictionary {
        return {:hrAbove => hr, :minVar => v};
    }

    function calm(bonusSec as Number, dropBpm as Number) as Dictionary {
        return {:maxVar => 3000, :maxHr => 90, :hrDropBonusSec => bonusSec, :hrDropBpm => dropBpm};
    }

    function build() as Array<Dictionary> {
        var sun = {:needHrAbove => 0, :wakeWindowH => 2};
        return [
            // exercises
            e(:jumpingJacks, "Jumping jacks", :exercise, :reps, :rep, 3.0, :yes, null, null, false, reps(600, 1600, 400, 1)),
            e(:squats, "Squats", :exercise, :reps, :rep, 6.0, :yes, null, null, false, reps(750, 1250, 900, 1)),
            e(:lunges, "Lunges", :exercise, :reps, :rep, 8.0, :yes, null, null, false, reps(750, 1250, 1000, 1)),
            e(:highKnees, "High knees", :exercise, :cadence, :sec, 3.0, :yes, null, null, false, {:minSpm => 140, :hrAbove => 20}),
            e(:march, "March in place", :exercise, :cadence, :sec, 1.5, :yes, null, null, false, {:minSpm => 80, :hrAbove => 0}),
            e(:plank, "Plank", :exercise, :hold, :sec, 3.0, :yes, null, null, false, hold(2500, :prone)),
            e(:forearmPlank, "Forearm plank", :exercise, :hold, :sec, 3.0, :yes, null, null, false, hold(2500, :prone)),
            e(:deadbug, "Deadbug", :exercise, :reps, :rep, 8.0, :yes, null, null, false, reps(700, 1300, 1200, 2)),
            e(:birdDog, "Bird-dogs", :exercise, :reps, :rep, 8.0, :partly, null, null, false, reps(700, 1300, 1200, 2)),
            e(:pushups, "Push-ups", :exercise, :tilt, :rep, 10.0, :partly, null, null, false, {:minDeg => 20, :minMs => 800}),
            e(:dips, "Chair dips", :exercise, :tilt, :rep, 10.0, :partly, null, null, false, {:minDeg => 15, :minMs => 800}),
            e(:mountainClimbers, "Mountain climbers", :exercise, :vigorous, :sec, 3.0, :partly, null, null, false, {:hrAbove => 30, :minVar => 40000}),
            e(:gluteBridges, "Glute bridges", :exercise, :hold, :sec, 2.0, :partly, null, null, false, hold(6000, :supine)),
            // chores and active
            e(:coldShower, "Cold shower", :chore, :cold, :sec, 4.0, :yes, 720, null, false, {:dropC => 3.0, :hrSpike => 10}),
            e(:stairs, "Stairs", :chore, :floors, :floor, 120.0, :yes, null, null, false, {}),
            e(:walk, "Walk or hike", :outdoor, :walk, :sec, 0.0, :yes, null, null, false, {}),
            e(:shovelOrMow, "Shovel snow or mow", :outdoor, :outdoors, :sec, 1.5, :yes, null, null, false, {:needHrAbove => 15, :wakeWindowH => 0}),
            e(:dance, "Dance party", :chore, :vigorous, :sec, 1.5, :yes, null, null, false, {:hrAbove => 30, :minVar => 40000}),
            e(:vacuum, "Vacuum, mop or sweep", :chore, :active, :sec, 1.0, :partly, null, 300, false, active(15, 8000)),
            e(:windows, "Clean windows", :chore, :active, :sec, 1.0, :partly, null, null, false, active(15, 8000)),
            e(:stretching, "Stretching", :chore, :active, :sec, 0.75, :partly, null, null, false, active(5, 2000)),
            e(:sunlight, "Morning sunlight", :outdoor, :outdoors, :sec, 1.0, :yes, 600, null, true, sun),
            // calm
            e(:meditation, "Meditation or breathing", :calm, :calm, :sec, 0.5, :yes, null, null, false, calm(300, 5)),
            e(:read, "Read a book", :calm, :calm, :sec, 0.5, :yes, null, null, false, calm(0, 0)),
            e(:origami, "Origami", :calm, :calm, :sec, 0.5, :partly, null, null, false, calm(0, 0)),
            e(:coloring, "Coloring or doodling", :calm, :calm, :sec, 0.5, :partly, null, null, false, calm(0, 0)),
            e(:embroidery, "Embroidery or cross-stitch", :calm, :calm, :sec, 0.5, :partly, null, null, false, calm(0, 0)),
            e(:crochet, "Crochet or punch needle", :calm, :calm, :sec, 0.5, :partly, null, null, false, calm(0, 0)),
            e(:puzzle, "Puzzle or diamond painting", :calm, :calm, :sec, 0.5, :partly, null, null, false, calm(0, 0))
        ];
    }

    function all() as Array<Dictionary> {
        if (_all == null) {
            _all = build();
        }
        return _all as Array<Dictionary>;
    }

    function get(id as Symbol) as Dictionary? {
        var a = all();
        for (var i = 0; i < a.size(); i++) {
            if (a[i][:id] == id) {
                return a[i];
            }
        }
        return null;
    }

    function ids() as Array<Symbol> {
        var a = all();
        var out = [] as Array<Symbol>;
        for (var i = 0; i < a.size(); i++) {
            out.add(a[i][:id] as Symbol);
        }
        return out;
    }
}
