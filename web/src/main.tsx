import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './design/tokens.css'
import './design/glass.css'
import './app.css'
import { App } from './App'
import { Gallery } from './gallery/Gallery'

const isGallery = location.hash.startsWith('#/gallery')
createRoot(document.getElementById('root')!).render(<StrictMode>{isGallery ? <Gallery /> : <App />}</StrictMode>)

if ('serviceWorker' in navigator && import.meta.env.PROD && !isGallery) {
  navigator.serviceWorker.register(`${import.meta.env.BASE_URL}sw.js`).catch(() => undefined)
}
