# Origins

AF64 was inspired by [Rabrg/artificial-life](https://github.com/Rabrg/artificial-life) and the Computational Life paper. The key insight from that work: artificial life simulations should be computationally cheap, with expensive intelligence firing only at decision points. The organisms live cheaply; they think expensively and selectively.

The framework was conceived during a walking conversation on the night of March 10, 2026. The starting question was simple: *"What if AI agents weren't chatbots that respond when spoken to, but organisms that live whether anyone is watching or not?"*

The terrarium metaphor followed: you don't talk to the fish — you watch them, feed them, adjust the conditions. The ecosystem runs on its own.

From there, the mechanics emerged:
- **Energy as universal currency** — because life requires metabolism
- **Drives as persistent hunger** — because organisms need motivation beyond task lists
- **Model tier as reward** — because cognition should be earned, not assigned
- **Metamorphosis over death** — because the seats are fixed but who sits in them evolves

The 64-agent structure draws from the I Ching — 64 hexagrams, each a unique combination of qualities. The number is fixed. The meaning shifts with the reading.

## Acknowledgments

- [Rabrg/artificial-life](https://github.com/Rabrg/artificial-life) — the seed
- The Computational Life paper — the theoretical foundation
- [Venice.ai](https://venice.ai) — LLM inference provider used in the reference implementation
