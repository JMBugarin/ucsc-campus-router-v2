import { GlassButton, GlassModal } from '../design/components'
import type { Help } from '../state/location'

/** Why the location didn't come through on this device, and the settings to change. */
export function LocationHelp({ help, onClose, onRetry, onPickOnMap }: { help: Help; onClose: () => void; onRetry: () => void; onPickOnMap?: () => void }) {
  return (
    <GlassModal open onClose={onClose} title={help.title}>
      <div className="lochelp">
        <p className="note">{help.body}</p>
        {help.steps.length > 0 && (
          <ol className="howto">
            {help.steps.map((s) => (
              <li key={s}>{s}</li>
            ))}
          </ol>
        )}
        <div className="audit__row">
          <GlassButton variant="primary" icon="locate" onClick={onRetry}>
            Try again
          </GlassButton>
          {onPickOnMap && (
            <GlassButton icon="pin" onClick={onPickOnMap}>
              Pick my start on the map
            </GlassButton>
          )}
          <GlassButton onClick={onClose}>Close</GlassButton>
        </div>
        <p className="note">You can still plan without it: pick a starting point on the map or search an address in Directions.</p>
      </div>
    </GlassModal>
  )
}
