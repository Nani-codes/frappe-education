FROM frappe/bench:latest

USER root
COPY init.sh entrypoint.sh /workspace/
RUN chmod +x /workspace/init.sh /workspace/entrypoint.sh \
	&& mkdir -p /home/frappe/frappe-bench \
	&& chown -R frappe:frappe /home/frappe/frappe-bench /workspace

WORKDIR /home/frappe
ENTRYPOINT ["/workspace/entrypoint.sh"]
