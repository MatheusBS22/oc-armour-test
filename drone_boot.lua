local dr=component.proxy(component.list("drone")())
local function st(s) if dr then dr.setStatusText(tostring(s):sub(1,50)) end end
local function tun()
  for a,_ in component.list("tunnel") do return component.proxy(a) end
end
local function log(s)
  st(s) local t=tun() if t then t.send(tostring(s)) end
end

-- Lista componentes
log("componentes:")
for addr,tipo in component.list() do
  log(tipo)
  computer.pullSignal(0.2)
end

-- Lista itens no inventario do drone
local ic=component.proxy(component.list("inventory_controller")())
if ic then
  local size=ic.getInventorySize(0)
  log("inv size:"..tostring(size))
  for i=1,size do
    local item=ic.getStackInSlot(0,i)
    if item then
      log("slot"..i..":"..tostring(item.name))
    end
  end
else
  log("sem inventory_controller")
end

st("done")
while true do computer.pullSignal(1) end
