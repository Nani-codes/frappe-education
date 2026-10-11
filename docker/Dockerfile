FROM frappe/bench:latest

USER root
COPY init.sh /workspace/init.sh
RUN chmod +x /workspace/init.sh \
	&& chown frappe:frappe /workspace/init.sh

USER frappe
WORKDIR /home/frappe

CMD ["bash", "/workspace/init.sh"]
