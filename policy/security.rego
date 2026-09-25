package security

default allow = false

# อนุญาตให้ Build ผ่านถ้าไม่มี CRITICAL vulnerabilities ใน audit.json
allow {
    input.metadata.vulnerabilities.critical == 0
}