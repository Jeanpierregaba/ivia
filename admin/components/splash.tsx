import { LogoTile } from "./brand";

// Le splash n'est joué qu'au premier chargement de l'onglet : ce script, lu avant l'affichage,
// le masque aussitôt pour les chargements suivants (aucun clignotement).
const once = `try{if(sessionStorage.getItem("ivia-splash"))document.documentElement.classList.add("splash-seen");else sessionStorage.setItem("ivia-splash","1")}catch(e){}`;

/** Écran d'ouverture : tuile ivia qui rebondit, mosaïque de la charte, barre de chargement. */
export function Splash() {
  return (
    <>
      <script dangerouslySetInnerHTML={{ __html: once }} />
      <div aria-hidden="true" className="splash">
        <div className="splash-mosaic">
          <span className="bg-primary [animation-delay:120ms]" />
          <span className="bg-secondary [animation-delay:200ms]" />
          <span className="bg-[#16365f] [animation-delay:280ms]" />
          <span className="bg-primary-strong [animation-delay:360ms]" />
        </div>
        <div className="splash-logo">
          <LogoTile size={92} />
        </div>
        <p className="splash-title">Back-office</p>
        <span className="splash-bar">
          <span />
        </span>
      </div>
    </>
  );
}
