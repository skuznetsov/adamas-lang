struct adamas_out_local_pair { int read_end; int write_end; };
int adamas_out_local_fill_pair(struct adamas_out_local_pair *pair) {
  pair->read_end = 65;
  pair->write_end = 66;
  return 0;
}
