package org.baorant.fileuplod.config;

import org.baorant.fileuplod.result.VerifyResultwebSocket;
import org.baorant.fileuplod.util.VideoStreamProcessor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.socket.server.standard.ServerEndpointExporter;
import jakarta.annotation.PostConstruct;

@Configuration
public class WebSocketConfig {

    @Bean
    public ServerEndpointExporter serverEndpointExporter() {
        return new ServerEndpointExporter();
    }

    @Autowired
    private VideoStreamProcessor videoStreamProcessor;

    @PostConstruct
    public void init() {
        VerifyResultwebSocket.setProcessor(videoStreamProcessor);
    }
}