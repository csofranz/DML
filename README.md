# DML 
A Toolbox For Mission Designers
(no Lua Required)

## What?
DML is a **mission-building toolbox** for Eagle Dynamic's DCS combat flight simulator. It contains many modules that all can do something for you. It’s built similar to a box of LEGO® bricks – you seldom need all, and you can start having fun building stuff knowing just the basics and using just a few.
Here are some examples:
-	Do you want to add a moving NDB to a ship? Just add the NDB module
-	Want to keep kill scores? Add the PlayerScore module.
-	How about dynamically spawn troops when you need? Look at Cloners.
-	Your mission needs random civilian traffic? Check out Civ Air.

Even better, **DML does not require Lua**, yet it also provides comprehensive support for Lua. 
At its heart are modules that attach themselves to Mission Editor’s (ME) Trigger Zones to provide new abilities. Mission designers control abilities in ME by adding ‘Attributes’ to these Trigger Zones.

![image](https://user-images.githubusercontent.com/21967811/150338060-10061782-c59c-46ac-8e42-ab598aae1fc9.png)

For example, when you add above attributes to a trigger zone, the “cfxNDB” module automatically activates for this zone, and starts an NDB at the zone’s center at 121.5 MHz, playing the “distressbeacon.ogg” sound file on that frequency.

Through this simple mechanism, adding complex new abilities to missions becomes a snap (or, at least, much easier). Since **you control DML from inside ME**, you do not have to mess around with Lua scripts – all DML modules take their run-time data from Trigger Zone attributes. You edit those in ME: Trigger Zones already have attributes, editing them is built into ME. If you have ever created a Trigger Zone, you have already seen ME’s zone attributes. You likely ignored them because they have had little practical use. Until now. We’ll use zone attributes to put DCS mission creation into super-cruise.

**DML can reduce advanced tasks (such as adding CSAR missions) to placing trigger zones and adding attributes.**

If that isn’t enough, DML modules **can be triggered with ME flags**, while others **can set ME Flags** when they activate. For example, spawn zones can be instructed to watch flag 100, and spawn every time when that flag changes its value. Other modules can be told to increase a Flag (e.g., 110) every time they activate. This allows you to integrate the modules in your normal ME mission design workflow without having to resorting to outside means.

![image](https://user-images.githubusercontent.com/21967811/150333268-21d8ede9-4846-4194-812b-dfdb35e8dac9.png)


If a module requires configuration data, it starts up with default values, and then looks for a – surprise! – Trigger Zone that might contain the attributes that you want to change for this mission. **You can configure your modules from within ME** – you don’t have to change a single line of code.

![image](https://user-images.githubusercontent.com/21967811/150333378-ad2908c4-b14b-42af-9b1b-ad6bc9993b92.png)


DML has something in store for every mission designer – novices and veterans alike. And for mission designers who have discovered Lua, DML can super-charge their abilities. That being said, **Lua knowledge is not required** to use DML in your missions. At all.

## Show Me!
Let us look at a real-life DML-enhanced mission:

 ![image](https://user-images.githubusercontent.com/21967811/150332973-0a517578-3967-400a-9b5c-1207b0fab53e.png)


Note the five Trigger Zones on the map (follow the unobtrusive red arrows). As mentioned, DML uses ME Trigger Zones and attaches its own modules to them. That way, mission designers can simply place new functionality by adding standard Trigger Zones to the map - without requiring any Lua. You then add a few attributes to the Trigger Zone, and DML’s modules home in on them automatically.

Above screenshot was taken from my ["Integrated Warfare: Pushback"](https://forums.eagle.ru/topic/276664-pushback-caucasus-integrated-warfare-multi-module-multi-player/), a mission that uses DML to dynamically create ground forces and that require the player’s air support to win. On the map, I placed various zones to

- Add conquerable zones (“Wolf Crossing”, “Bride’s Bridge”, “Highroad”) – these are zones that, when captured by blue or red, automatically produce ground forces that defend the zone against invaders and seek out and capture other conquerable zones
- Control civilian air traffic (“Traffic: Civilian”)
- Control AI’s pathing for ground forces (“pathing off”)

All zones use simple, ME editable attributes (like “pathing”, “offroad”) to tell DML what to do. In the end, writing such a mission amounts to just a little more than placing zones and adding attributes. After all, the trick is coming up with a good mission idea – putting it together should be easy. With DML it may have become a bit easier.

![image](https://user-images.githubusercontent.com/21967811/150333527-15e2af24-8598-4177-801f-8dabcd75baf8.png)


Behind the scenes, DML also provides a collection of **Foundation** modules that lack ME integration. Using these modules directly is not intended for beginners and requires a modicum of Lua-knowledge; they provide ready-made, tested, convenient access to many functions that mission designers would traditionally code by themselves (or use ready-made libraries).

## What is in the box?
So, what’s in DML right now? In a nutshell here’s what you get:
- **Drop-in Modules (no Lua knowledge required)** that add complete functionality to a mission – for example
  - CSAR Missions
  - Limited number of pilots (ties in with CSAR Missions)
  - Civilian Air traffic
  - Automatic Recon Mode
  - Slot Blocking Client (SSB based) for preventing spawns on enemy airfields
  - Protection from missiles
  - Helicopter Troop Pick-up, Transport and Deployment
  - Score Keeping
- **Zone Enhancements** that interactively **attach new functionality to Zones in ME (no Lua required)**. They provide diverse functionality such as
  - Dynamic Ground Troop Spawning
  - Dynamic Object/Cargo Spawning
  - Artillery Target Zones
  - Conquerable Zones and FARPS
  - (moving) NDB
  - Map/Scenery Object destruction Detector 
- **Persistence** – players can **save a mission and then later continue** it (within the confines of DCS’s limitations)
- An **Interactive Debugger** to inspect flag values, report any time they change their value or if their value changes to a specific number – with ME integration that allows you to set up debugging missions before you run them
- **Foundation**, a library of ready-to-use methods **(only for mission designers who use Lua)**. They support
  - Advanced Event Handlers for mission and player events
  - Zone management and attaching/reading zone attributes
  - Inventory keeping
  - Managing orders and pathing for troops
- **Multi-player supported out-of-the-box**. All modules work for single- and multiplayer missions, including modules with user interaction via communications.
- **A collection of fully documented Tutorials / Demos** that serve to illustrate how the more salient points of DML can be used to quickly create great mission. They aren’t flashy. They hopefully are helpful instead. 
- **A hefty Manual** that I can lord over you and yell “RTFM” whenever you have a question. Yup, that’s definitely why I wrote it.

Of course, this is just the beginning – DML is far from complete, and there are lots of new avenues to explore. Based on feedback, I expect DML to evolve, and to add new and exciting abilities. Until then, I hope that you enjoy the ride!

-ch
