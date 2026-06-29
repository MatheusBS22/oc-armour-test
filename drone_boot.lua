local dr=component.proxy(component.list("drone")())
local function st(s) if dr then dr.setStatusText(tostring(s):sub(1,50)) end end
local function tun()
  for a,_ in component.list("tunnel") do return component.proxy(a) end
end
local function log(s)
  st(s) local t=tun() if t then t.send(tostring(s)) end
end

log("testando inv...")

-- O drone acessa seu proprio inventario via componente drone
if dr then
  local ok,size=pcall(function() return dr.inventorySize() end)
  log("drone.inventorySize: "..tostring(ok).." "..tostring(size))
  if ok and size then
    for i=1,size do
      local ok2,item=pcall(function() return dr.getStackInSlot(i) end)
      if ok2 and item then
        log("slot"..i..":"..tostring(item.name))
      end
    end
  end
end

-- Tenta inventory_controller com sides diferentes
local ic=component.proxy(component.list("inventory_controller")())
if ic then
  for side=0,5 do
    local ok,size=pcall(function() return ic.getInventorySize(side) end)
    if ok and size then
      log("ic side"..side.." size:"..tostring(size))
    end
  end
end

st("done")
while true do computer.pullSignal(1) end
