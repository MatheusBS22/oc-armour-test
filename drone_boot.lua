local d=component.proxy(component.list("drone")())
local function status(s) if d then d.setStatusText(s:sub(1,100)) end end
status("Baixando...")
local i=component.proxy(component.list("internet")())
local h=i.request("https://raw.githubusercontent.com/MatheusBS22/oc-armour-test/main/drone.lua")
local c=""
repeat local x=h.read(512) if x then c=c..x end until not x
status("Bytes:"..#c)
local fn,err=load(c)
if not fn then status("LOAD ERR:\n"..(err or "?"):sub(1,80)) while true do computer.pullSignal(1) end end
status("Rodando...")
local ok,e=pcall(fn)
if not ok then status("RUN ERR:\n"..tostring(e):sub(1,80)) while true do computer.pullSignal(1) end end
