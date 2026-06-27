# Throwaway sandbox for teleport e2e tests: real sshd + git + rsync + tmux,
# never the host $HOME. Source and target are the same container (ssh to self),
# which still exercises the full packaging → ssh transport → rsync → receive path.
FROM debian:stable-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      openssh-server git python3 tmux rsync ca-certificates procps \
 && rm -rf /var/lib/apt/lists/*

# Fake `claude`: the receiver lands the session in `tmux ... claude -r <SID>`.
# A real claude isn't present, so stand in with something that stays alive long
# enough for the "tmux session is running" assertion. Installed on PATH for
# non-interactive ssh (sshd's exec PATH includes /usr/bin).
RUN printf '#!/bin/sh\nexec sleep 3600\n' > /usr/bin/claude && chmod +x /usr/bin/claude

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
