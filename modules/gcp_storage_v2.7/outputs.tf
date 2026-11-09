output "bucket_name" {
  value       = google_storage_bucket.base.name
  description = "The name of the bucket"
}
