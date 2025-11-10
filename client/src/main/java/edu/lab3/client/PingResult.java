package edu.lab3.client;

public  class PingResult {
    public String status;
    public double latencySec;
    public Object backend;
    public String backendUrl;
    public PingResult(String status, double latencySec, Object backend, String backendUrl) {
        this.status = status;
        this.latencySec = latencySec;
        this.backend = backend;
        this.backendUrl = backendUrl;
    }
}
