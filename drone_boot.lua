local i=component.proxy(component.list("internet")())
local h=i.request("https://raw.githubusercontent.com/MatheusBS22/oc-armour-test/main/drone.lua")
local c=""
repeat local d=h.read(512) if d then c=c..d end until not d
assert(load(c))()
