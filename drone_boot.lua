local dr=component.proxy(component.list("drone")())
local function st(s) if dr then dr.setStatusText(tostring(s):sub(1,50)) end end
st("boot")
local i=component.proxy(component.list("internet")())
if not i then st("SEM INET") while true do computer.pullSignal(1) end end
st("req...")
local h=i.request("https://raw.githubusercontent.com/MatheusBS22/oc-armour-test/main/drone.lua")
h.finishConnect()
local c=""
repeat
  local d,e=h.read(512)
  if d then c=c..d
  elseif e then st("ERR READ:"..tostring(e)) while true do computer.pullSignal(1) end end
until not d
h.close()
st("bytes:"..#c)
computer.pullSignal(0.5)
local fn,err=load(c)
if not fn then st("SYN:"..tostring(err):sub(1,50)) while true do computer.pullSignal(1) end end
st("run")
local ok,e=pcall(fn)
if not ok then st("ERR:"..tostring(e):sub(1,50)) while true do computer.pullSignal(1) end end
