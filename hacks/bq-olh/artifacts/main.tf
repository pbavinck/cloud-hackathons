# 1. PROVIDER & VARIABLES
# Defining variables makes the script reusable across environments.

# 2. ENABLE SERVICES (APIs)
# This replaces the 'gcloud services enable' block.
locals {
  bucket_name = "${var.gcp_project_id}-raw"
}

resource "google_project_service" "enabled_apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "bigquerydatapolicy.googleapis.com",
    "biglake.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dataproc.googleapis.com",
    "compute.googleapis.com",
    "orgpolicy.googleapis.com",
    "aiplatform.googleapis.com",
    "dataform.googleapis.com"
  ])
  service  = each.key
  disable_on_destroy = false
}

# 3. IAM ROLES FOR THE USER
resource "google_project_iam_member" "user_roles" {
  for_each = toset([
    "roles/compute.admin",
    "roles/bigquery.admin",
    "roles/storage.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/dataproc.admin",
    "roles/aiplatform.colabEnterpriseAdmin",
    "roles/aiplatform.user"
  ])
  project = var.gcp_project_id
  role    = each.key
  member  = "user:${var.gcp_user}" 
}

# 4. IAM ROLES FOR COMPUTE SERVICE ACCOUNT
data "google_project" "project" {}

resource "google_project_iam_member" "compute_sa_roles" {
  for_each = toset([
    "roles/dataproc.worker",
    "roles/bigquery.connectionAdmin",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/bigquery.admin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/compute.admin",
    "roles/aiplatform.colabEnterpriseAdmin"
  ])
  project = var.gcp_project_id
  role    = each.key
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

#5. NETWORKING (VPC, SUBNET, ROUTER, GATEWAY)
resource "google_compute_network" "olh_net" {
  name                    = "olh-net"
  auto_create_subnetworks = false # Matches --subnet-mode=custom
}

resource "google_compute_subnetwork" "olh_subnet" {
  name                     = "olh-net-${var.gcp_region}"
  network                  = google_compute_network.olh_net.id
  ip_cidr_range            = "10.1.0.0/24"
  region                   = var.gcp_region
  private_ip_google_access = true # Matches --enable-private-ip-google-access
}

resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal-ingress"
  network = google_compute_network.olh_net.name

  allow {
    protocol = "all"
  }

  source_ranges      = ["10.1.0.0/24"]
  destination_ranges = ["10.1.0.0/24"]
}

resource "google_compute_firewall" "allow_ssh" {
  name          = "allow-ssh-from-console"
  network       = google_compute_network.olh_net.name
  source_ranges = ["35.235.240.0/20"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_router" "router" {
  name    = "olh-router"
  region  = google_compute_subnetwork.olh_subnet.region
  network = google_compute_network.olh_net.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "olh-router-nat"
  router                             = google_compute_router.router.name
  region                             = google_compute_router.router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# 6. STORAGE (GCS BUCKET)
resource "google_storage_bucket" "raw_data" {
  name                        = local.bucket_name
  location                    = var.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
}

# 7. BIGQUERY DATASET
resource "google_bigquery_dataset" "marketing" {
  dataset_id = "marketing"
  location   = var.gcp_region
}

# 9. DATA LOADING
resource "google_compute_instance" "startup-vm" {
  description  = "Runs a dynamic script to use gcloud/bq commands"
  name         = "startup-vm"
  machine_type = "e2-micro"
  zone         = var.gcp_zone
  tags         = ["http-server"]

  depends_on = [
    google_project_iam_binding.compute_sa,
    google_compute_router_nat.nat
  ]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  shielded_instance_config {
    enable_secure_boot = true
    enable_vtpm        = true
  }

  network_interface {
    subnetwork = google_compute_subnetwork.olh_subnet.name
  }

  service_account {
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/startup_script.tftpl", {
    gcp_project_id   = var.gcp_project_id,
    gcp_region       = var.gcp_region,
    gcp_zone         = var.gcp_zone,
    gcs_bucket       = google_storage_bucket.raw_data.name
    nat_gateway_name = google_compute_router_nat.nat.name
    router_name      = google_compute_router.router.name
    network_name     = google_compute_network.olh_net.name
    subnet_name      = google_compute_subnetwork.olh_subnet.name
  })
}

# Grant Project IAM Admin role to compute@developer service account 
# (add permissions as necessary for what commands you need to run)
resource "google_project_iam_binding" "compute_sa" {
  role    = "roles/resourcemanager.projectIamAdmin"
  project = var.gcp_project_id
  members = [
    "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com",
  ]
}
