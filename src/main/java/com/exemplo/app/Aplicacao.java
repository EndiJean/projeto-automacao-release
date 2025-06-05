package com.exemplo.app;

import java.io.IOException;
import java.io.InputStream;
import java.util.Properties;

public class Aplicacao {
    public static void main(String[] args) {
        System.out.println("Aplicação de Exemplo Iniciada!");
        String versao = "";
        try (InputStream input = Aplicacao.class.getClassLoader().getResourceAsStream("application.properties")) {
            Properties prop = new Properties();
            if (input == null) {
                System.out.println("Desculpe, não foi possível encontrar application.properties");
                return;
            }
            prop.load(input);
            versao = prop.getProperty("app.version");
            System.out.println("Versão da Aplicação: " + versao);
        } catch (IOException ex) {
            ex.printStackTrace();
        }

        // Leria o arquivo configuracao_release.txt se fosse um caso de uso real
        // System.out.println("Lendo configuração do arquivo gerado...");
        // try {
        //     List<String> lines = Files.readAllLines(Paths.get("target/configuracao_release.txt"));
        //     lines.forEach(System.out::println);
        // } catch (IOException e) {
        //     e.printStackTrace();
        // }

        System.out.println("Aplicação de Exemplo Encerrada.");
    }
}