set -ex

tmpdir=$(mktemp --directory --suffix "-agama")
echo "working on $tmpdir"

/usr/bin/sleep 30

cat << EOF > ${tmpdir}/profile.json
{
   "software": {
      "product": "Tumbleweed"
   },
   "user": {
      "fullName": "Jane Doe",
      "password": "doe",
      "userName": "joe"
   },
   "root": {
      "password": "nots3cr3t"
   }
}
EOF

/usr/bin/agama profile validate "${tmpdir}/profile.json" || echo "Validation failed"
/usr/bin/agama config load "${tmpdir}/profile.json"

/usr/bin/agama install
/sbin/reboot
