local dr=component.proxy(component.list("drone")())
local function st(s) if dr then dr.setStatusText(tostring(s):sub(1,50)) end end
local function tun()
  for a,_ in component.list("tunnel") do return component.proxy(a) end
end
local function log(s)
  st(s) local t=tun() if t then t.send(tostring(s)) end
end
log("listando...")
for addr,tipo in component.list() do
  log(tipo)
  computer.pullSignal(0.2)
end
st("done")
while true do computer.pullSignal(1) end
