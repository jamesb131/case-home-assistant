import "./halloween.css";

export default function HalloweenDecor() {
  return (
    <div className="halloweenDecor" aria-hidden="true">
      <svg className="halloweenWeb" viewBox="0 0 160 160" fill="none">
        <path d="M0 0L160 0M0 0L148 61M0 0L113 113M0 0L61 148M0 0L0 160M38 0Q32 12 35 14Q24 20 27 27Q15 27 14 35Q5 31 0 38M76 0Q64 23 70 29Q49 38 54 54Q32 53 29 70Q11 64 0 76M114 0Q97 35 105 44Q74 57 81 81Q48 80 44 105Q17 96 0 114M152 0Q129 47 140 58Q98 76 108 108Q64 107 58 140Q23 129 0 152" />
      </svg>
      <svg className="halloweenPumpkin" viewBox="0 0 150 130" fill="none">
        <path d="M72 35Q64 12 86 8L89 19Q74 19 83 36" fill="#73844c" />
        <ellipse cx="47" cy="79" rx="34" ry="42" fill="#e97822" />
        <ellipse cx="103" cy="79" rx="34" ry="42" fill="#e97822" />
        <ellipse cx="75" cy="79" rx="35" ry="46" fill="#ff9b36" />
        <path d="M38 70L57 53L64 76ZM86 76L93 53L112 70ZM69 84L76 74L83 84ZM39 90L57 97L62 91L70 102L82 102L89 91L94 97L112 90Q101 117 76 116Q51 116 39 90Z" fill="#382039" />
      </svg>
      <span className="halloweenLabel">Happy Halloween</span>
    </div>
  );
}
