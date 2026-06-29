local dr=component.proxy(component.list("drone")())
local function st(s) if dr then dr.setStatusText(tostring(s):sub(1,50)) end end
local function tun()
  for a,_ in component.list("tunnel") do return component.proxy(a) end
end
local function log(s)
  st(s) local t=tun() if t then t.send(tostring(s)) end
end
st("boot")
local i=component.proxy(component.list("internet")())
if not i then st("SEM INET") while true do computer.pullSignal(1) end end
local h=i.request("https://raw.githubusercontent.com/MatheusBS22/oc-armour-test/main/drone.lua")
h.finishConnect()
local c=""
repeat local d=h.read(512) if d then c=c..d end until not d
h.close()
st("bytes:"..#c)
computer.pullSignal(0.3)
local fn,err=load(c)
if not fn then
  log("SYN:"..tostring(err))
  while true do computer.pullSignal(1) end
end
st("run")
local ok,e=pcall(fn)
if not ok then
  log("ERR:"..tostring(e))
  while true do computer.pullSignal(1) end
end
