local ADDON, ns = ...

local Fade = {}
ns.Fade = Fade

local active = {}

local ticker = CreateFrame("Frame")

-- Duration is the time a full transparent to opaque sweep takes, so a fade that
-- gets interrupted part way through carries on from wherever it was rather than
-- snapping back to the start.
local function onUpdate(_, elapsed)
	local remaining = false

	for frame, fade in pairs(active) do
		local alpha = frame:GetAlpha()
		local step = elapsed / fade.duration

		if fade.target > alpha then
			alpha = math.min(fade.target, alpha + step)
		else
			alpha = math.max(fade.target, alpha - step)
		end

		frame:SetAlpha(alpha)

		if alpha == fade.target then
			active[frame] = nil
			if fade.finished then
				fade.finished(frame)
			end
		else
			remaining = true
		end
	end

	-- Derived from the table rather than a counter, so the ticker can never be
	-- switched off while something is still mid fade.
	if not remaining then
		ticker:SetScript("OnUpdate", nil)
	end
end

function Fade:Cancel(frame)
	active[frame] = nil
end

function Fade:To(frame, target, duration, finished)
	if not duration or duration <= 0 then
		self:Cancel(frame)
		frame:SetAlpha(target)
		if finished then
			finished(frame)
		end
		return
	end

	active[frame] = { target = target, duration = duration, finished = finished }
	ticker:SetScript("OnUpdate", onUpdate)
end

function Fade:IsFading(frame)
	return active[frame] ~= nil
end
