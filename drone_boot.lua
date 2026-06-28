local d=component.proxy(component.list("drone")())
local function status(s) if d then d.setStatusText(s) end end
status("Baixando...")
local i=component.proxy(component.list("internet")())
local h=i.request("https://raw.githubusercontent.com/MatheusBS22/oc-armour-test/main/drone.lua")
local c=""
repeat local x=h.read(512) if x then c=c..x end until not x
status("Executando...")
local fn,err=load(c)
if not fn then status("ERRO LOAD:\n"..(err or "?")) while true do computer.pullSignal(1) end end
local ok,e=pcall(fn)
if not ok then status("ERRO RUN:\n"..(tostring(e) or "?")) while true do computer.pullSignal(1) end end
