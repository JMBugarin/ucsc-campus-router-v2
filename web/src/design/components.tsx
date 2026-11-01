import {
  useCallback,
  useEffect,
  useId,
  useRef,
  useState,
  type ButtonHTMLAttributes,
  type CSSProperties,
  type HTMLAttributes,
  type KeyboardEvent,
  type PointerEvent as RPointerEvent,
  type ReactNode,
} from 'react'
import { createPortal } from 'react-dom'
import { Icon, type IconName } from './icons'
import { useAdaptiveStrength } from './adaptive'

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ')

/* ------------------------------------------------------------------ GlassPanel / Card */
type PanelProps = HTMLAttributes<HTMLDivElement> & {
  elevation?: 'floating' | 'raised' | 'flat'
  adaptive?: boolean
  as?: 'div' | 'section' | 'aside' | 'nav'
}

export function GlassPanel({ elevation = 'floating', adaptive = true, className, as: Tag = 'div', ...rest }: PanelProps) {
  const ref = useRef<HTMLDivElement>(null)
  useAdaptiveStrength(ref, adaptive)
  return <Tag ref={ref as never} className={cx('glass', elevation === 'raised' && 'glass--raised', elevation === 'flat' && 'glass--flat', className)} {...rest} />
}

/** A nested surface (radius 12): flat wash, no heavy card box around list items. */
export function GlassCard({ selected, className, ...rest }: HTMLAttributes<HTMLDivElement> & { selected?: boolean }) {
  return (
    <div
      className={cx(className)}
      style={{
        borderRadius: 'var(--r-card)',
        background: selected ? 'var(--accent-wash)' : 'var(--fill)',
        boxShadow: selected ? 'inset 0 0 0 1px var(--accent-line)' : 'inset 0 0 0 1px var(--divider)',
        padding: 'var(--s-m)',
      }}
      {...rest}
    />
  )
}

/* ------------------------------------------------------------------ Buttons */
type BtnProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'secondary' | 'primary' | 'ghost'
  size?: 'm' | 's'
  icon?: IconName
  force?: 'hover' | 'press' | 'disabled'
}

export function GlassButton({ variant = 'secondary', size = 'm', icon, force, className, children, type = 'button', ...rest }: BtnProps) {
  return (
    <button type={type} data-force={force} className={cx('gbtn', variant !== 'secondary' && `gbtn--${variant}`, size === 's' && 'gbtn--s', className)} {...rest}>
      {icon && <Icon name={icon} size={size === 's' ? 15 : 17} />}
      {children}
    </button>
  )
}

export function GlassIconButton({ icon, label, size = 'm', variant = 'ghost', force, className, ...rest }: Omit<BtnProps, 'children'> & { icon: IconName; label: string }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      data-force={force}
      className={cx('gbtn', 'gbtn--icon', variant !== 'secondary' && `gbtn--${variant}`, size === 's' && 'gbtn--s', className)}
      {...rest}
    >
      <Icon name={icon} size={size === 's' ? 16 : 19} />
    </button>
  )
}

export function GlassToolbar({ children, vertical = true, label, className }: { children: ReactNode; vertical?: boolean; label: string; className?: string }) {
  return (
    <GlassPanel
      as="nav"
      elevation="raised"
      aria-label={label}
      className={cx('gtoolbar', className)}
      style={{ display: 'flex', flexDirection: vertical ? 'column' : 'row', gap: 2, padding: 4, borderRadius: 'var(--r-sheet)' }}
    >
      {children}
    </GlassPanel>
  )
}

/* ------------------------------------------------------------------ Search */
export function GlassSearch({
  value,
  onChange,
  onSubmit,
  onFocus,
  onEscape,
  onNav,
  placeholder,
  label,
  listId,
  activeId,
  expanded,
  loading,
  force,
  leading,
  inputRef,
}: {
  value: string
  onChange: (v: string) => void
  onSubmit?: () => void
  onFocus?: () => void
  onEscape?: () => void
  onNav?: (dir: 1 | -1) => void
  placeholder?: string
  label: string
  listId?: string
  activeId?: string
  expanded?: boolean
  loading?: boolean
  force?: 'focus'
  leading?: ReactNode
  inputRef?: React.Ref<HTMLInputElement>
}) {
  return (
    <div className="gsearch" data-force={force}>
      {leading ?? <Icon name="search" size={18} />}
      <input
        ref={inputRef}
        type="search"
        role="combobox"
        aria-label={label}
        aria-autocomplete="list"
        aria-controls={listId}
        aria-expanded={expanded ?? false}
        aria-activedescendant={activeId}
        autoComplete="off"
        autoCorrect="off"
        spellCheck={false}
        enterKeyHint="search"
        value={value}
        placeholder={placeholder}
        onChange={(e) => onChange(e.target.value)}
        onFocus={onFocus}
        onKeyDown={(e: KeyboardEvent<HTMLInputElement>) => {
          if (e.key === 'Enter') onSubmit?.()
          if (e.key === 'Escape') onEscape?.()
          if (e.key === 'ArrowDown') (e.preventDefault(), onNav?.(1))
          if (e.key === 'ArrowUp') (e.preventDefault(), onNav?.(-1))
        }}
      />
      {loading && <span className="gspinner" role="status" aria-label="Loading" />}
      {value && !loading && <GlassIconButton icon="close" label="Clear search" size="s" onClick={() => onChange('')} />}
    </div>
  )
}

/* ------------------------------------------------------------------ Flat list */
export function GlassList({ children, label, id, className }: { children: ReactNode; label: string; id?: string; className?: string }) {
  return (
    <ul id={id} role="listbox" aria-label={label} className={cx('glist', className)}>
      {children}
    </ul>
  )
}

export function GlassListRow({
  id,
  icon,
  iconColor,
  title,
  subtitle,
  trailing,
  selected,
  disabled,
  force,
  onClick,
}: {
  id?: string
  icon?: IconName
  iconColor?: string
  title: ReactNode
  subtitle?: ReactNode
  trailing?: ReactNode
  selected?: boolean
  disabled?: boolean
  force?: 'hover' | 'selected'
  onClick?: () => void
}) {
  return (
    <li role="presentation">
      <button
        id={id}
        role="option"
        type="button"
        aria-selected={!!selected}
        aria-disabled={disabled || undefined}
        data-force={force}
        className="glist__row"
        onClick={onClick}
      >
        {icon && (
          <span className="glist__icon" style={iconColor ? { color: iconColor } : undefined}>
            <Icon name={icon} size={19} />
          </span>
        )}
        <span className="glist__main">
          <span className="glist__title" style={{ display: 'block' }}>{title}</span>
          {subtitle && <span className="glist__sub" style={{ display: 'block' }}>{subtitle}</span>}
        </span>
        {trailing && <span className="glist__trail">{trailing}</span>}
      </button>
    </li>
  )
}

export const SectionLabel = ({ children }: { children: ReactNode }) => <div className="gsection">{children}</div>
export const Divider = () => <hr className="gdivider" />
export const Spinner = ({ label = 'Loading' }: { label?: string }) => <span className="gspinner" role="status" aria-label={label} />

export function StatusPill({ tone = 'accent', children }: { tone?: 'accent' | 'success' | 'warning' | 'danger'; children: ReactNode }) {
  const c = tone === 'accent' ? '--accent-rgb' : `--${tone}-rgb`
  return (
    <span className="gpill" style={{ ['--c' as string]: `var(${c})` } as CSSProperties}>
      <i />
      {children}
    </span>
  )
}

/* ------------------------------------------------------------------ Segmented / Switch / Banner */
export function GlassSegmentedControl<T extends string>({
  value,
  options,
  onChange,
  label,
}: {
  value: T
  options: { value: T; label: ReactNode; icon?: IconName }[]
  onChange: (v: T) => void
  label: string
}) {
  const idx = Math.max(0, options.findIndex((o) => o.value === value))
  return (
    <div role="radiogroup" aria-label={label} className="gseg" style={{ ['--n' as string]: options.length, ['--i' as string]: idx } as CSSProperties}>
      <span className="gseg__thumb" />
      {options.map((o, i) => (
        <button
          key={o.value}
          type="button"
          role="radio"
          aria-checked={o.value === value}
          className="gseg__opt"
          onClick={() => onChange(o.value)}
          onKeyDown={(e) => {
            if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
              const j = (i + (e.key === 'ArrowRight' ? 1 : -1) + options.length) % options.length
              onChange(options[j].value)
              ;(e.currentTarget.parentElement?.children[j + 1] as HTMLElement | undefined)?.focus()
            }
          }}
        >
          {o.icon && <Icon name={o.icon} size={14} />}
          {o.label}
        </button>
      ))}
    </div>
  )
}

export function GlassSwitch({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return <button type="button" role="switch" aria-checked={checked} aria-label={label} disabled={disabled} className="gswitch" onClick={() => onChange(!checked)} />
}

export function GlassBanner({
  tone = 'accent',
  title,
  children,
  action,
}: {
  tone?: 'accent' | 'success' | 'warning' | 'danger'
  title?: ReactNode
  children?: ReactNode
  action?: ReactNode
}) {
  const icon: IconName = tone === 'danger' || tone === 'warning' ? 'warn' : tone === 'success' ? 'check' : 'info'
  return (
    <div className={cx('gbanner', tone !== 'accent' && `gbanner--${tone}`)} role={tone === 'danger' ? 'alert' : 'status'}>
      <Icon name={icon} size={17} />
      <div style={{ flex: 1, minWidth: 0 }}>
        {title && <div className="gbanner__title">{title}</div>}
        {children && <div className="gbanner__body">{children}</div>}
      </div>
      {action}
    </div>
  )
}

/* ------------------------------------------------------------------ Tooltip */
export function GlassTooltip({ text, children, side = 'left', force }: { text: string; children: ReactNode; side?: 'left' | 'top' | 'bottom'; force?: 'show' }) {
  const id = useId()
  const pos: CSSProperties =
    side === 'left' ? { right: 'calc(100% + 10px)', top: '50%', transform: 'translateY(-50%)' } : side === 'top' ? { bottom: 'calc(100% + 8px)', left: '50%', transform: 'translateX(-50%)' } : { top: 'calc(100% + 8px)', left: '50%', transform: 'translateX(-50%)' }
  return (
    <span className="gtip-host" aria-describedby={id}>
      {children}
      <span id={id} role="tooltip" data-force={force} className="gtip glass glass--raised glass--card" style={pos}>
        {text}
      </span>
    </span>
  )
}

/* ------------------------------------------------------------------ Modal */
export function GlassModal({ open, onClose, title, children, inline }: { open: boolean; onClose: () => void; title: string; children: ReactNode; inline?: boolean }) {
  const ref = useRef<HTMLDivElement>(null)
  const prev = useRef<Element | null>(null)
  useEffect(() => {
    if (!open || inline) return
    prev.current = document.activeElement
    ref.current?.focus()
    return () => (prev.current as HTMLElement | null)?.focus?.()
  }, [open, inline])
  if (!open) return null
  const dialog = (
    <div className="gscrim" onMouseDown={(e) => e.target === e.currentTarget && onClose()} style={inline ? { position: 'relative', inset: 'auto', padding: 0, background: 'none', animation: 'none' } : undefined}>
      <GlassPanel
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        className="gmodal"
        {...({ ref } as object)}
        onKeyDown={(e) => {
          if (e.key === 'Escape') onClose()
          if (e.key === 'Tab') {
            const f = ref.current?.querySelectorAll<HTMLElement>('button,[href],input,[tabindex]:not([tabindex="-1"])')
            if (!f?.length) return
            const first = f[0]
            const last = f[f.length - 1]
            if (e.shiftKey && document.activeElement === first) (e.preventDefault(), last.focus())
            else if (!e.shiftKey && document.activeElement === last) (e.preventDefault(), first.focus())
          }
        }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
          <h2 style={{ flex: 1 }}>{title}</h2>
          <GlassIconButton icon="close" label="Close" size="s" onClick={onClose} />
        </div>
        {children}
      </GlassPanel>
    </div>
  )
  return inline ? dialog : createPortal(dialog, document.body)
}

/* ------------------------------------------------------------------ Sheet (mobile) */
export type Detent = 'peek' | 'half' | 'full'
const DETENT_VH: Record<Detent, number> = { peek: 0, half: 0.46, full: 0.9 }
const PEEK_PX = 150

export function GlassSheet({
  detent,
  onDetent,
  children,
  label,
  inline,
}: {
  detent: Detent
  onDetent: (d: Detent) => void
  children: ReactNode
  label: string
  inline?: boolean
}) {
  const [drag, setDrag] = useState<number | null>(null)
  const start = useRef<{ y: number; h: number } | null>(null)
  const ref = useRef<HTMLDivElement>(null)
  useAdaptiveStrength(ref)

  const heightFor = useCallback((d: Detent) => (d === 'peek' ? PEEK_PX : Math.round(window.innerHeight * DETENT_VH[d])), [])
  const h = drag ?? heightFor(detent)

  const down = (e: RPointerEvent) => {
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    start.current = { y: e.clientY, h: heightFor(detent) }
  }
  const move = (e: RPointerEvent) => {
    if (!start.current) return
    const next = start.current.h + (start.current.y - e.clientY)
    setDrag(Math.max(PEEK_PX - 20, Math.min(window.innerHeight * 0.92, next)))
  }
  const up = () => {
    if (!start.current) return
    const cur = drag ?? start.current.h
    const moved = Math.abs(cur - start.current.h)
    start.current = null
    setDrag(null)
    if (moved < 6) return onDetent(detent === 'peek' ? 'half' : detent === 'half' ? 'full' : 'peek')
    const opts: Detent[] = ['peek', 'half', 'full']
    onDetent(opts.reduce((a, b) => (Math.abs(heightFor(b) - cur) < Math.abs(heightFor(a) - cur) ? b : a)))
  }

  return (
    <div
      ref={ref}
      role="region"
      aria-label={label}
      data-detent={detent}
      data-dragging={drag !== null}
      className="gsheet glass"
      style={{ ['--sheet-h' as string]: `${h}px`, ...(inline ? { position: 'relative', left: 'auto', right: 'auto', bottom: 'auto' } : null) } as CSSProperties}
    >
      <div className="gsheet__grab" onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up} role="button" tabIndex={0} aria-label="Resize panel" onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && onDetent(detent === 'full' ? 'peek' : detent === 'half' ? 'full' : 'half')}>
        <i />
      </div>
      <div className="gsheet__body">{children}</div>
    </div>
  )
}

