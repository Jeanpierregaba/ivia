// Chaque changement de page rejoue l'entrée du contenu : fondu, léger glissement et netteté qui
// revient (le gabarit est recréé à chaque navigation, la barre latérale reste en place).
export default function Template({ children }: { children: React.ReactNode }) {
  return <div className="page-enter">{children}</div>;
}
