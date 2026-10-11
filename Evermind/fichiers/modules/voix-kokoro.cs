// EvermindVoix.exe : la voix d'Evermind (Kokoro, synthèse vocale récente, sur le PC, sans Internet).
// Le texte est d'abord transformé en sons du français (espeak-ng), puis Kokoro les prononce : les mots sont
// lus comme en français (« salut » se dit « salu »). Le moteur est sherpa-onnx (licence Apache 2.0,
// github.com/k2-fsa/sherpa-onnx), compilé avec le compilateur C# de Windows (.NET Framework 4, C# 5).
//
// Lancement : EvermindVoix.exe <dossier du modèle> [fils de calcul]
// Le modèle est chargé une seule fois, puis le programme attend des demandes, une par ligne (UTF-8) :
//   PARLE <tab> voix (numéro de la voix) <tab> vitesse <tab> étapes (non utilisé) <tab> fichier.wav <tab> texte
// et répond une ligne : « OK <tab> fichier.wav <tab> durée en secondes » ou « ERREUR <tab> message ».
// Il écrit « PRET » quand le modèle est chargé, et s'arrête quand l'entrée se ferme.
using System;
using System.Globalization;
using System.IO;
using System.Text;
using SherpaOnnx;

static class EvermindVoix
{
    static int Main(string[] args)
    {
        Console.InputEncoding = new UTF8Encoding(false);
        Console.OutputEncoding = new UTF8Encoding(false);
        if (args.Length < 1) { Console.WriteLine("ERREUR\tdossier du modèle manquant"); return 1; }
        string dossier = args[0];
        int fils = args.Length > 1 ? int.Parse(args[1]) : 4;
        OfflineTts tts;
        try
        {
            var cfg = new OfflineTtsConfig();
            cfg.Model.Kokoro.Model = Path.Combine(dossier, "model.onnx");
            cfg.Model.Kokoro.Voices = Path.Combine(dossier, "voices.bin");
            cfg.Model.Kokoro.Tokens = Path.Combine(dossier, "tokens.txt");
            cfg.Model.Kokoro.DataDir = Path.Combine(dossier, "espeak-ng-data");
            cfg.Model.Kokoro.Lang = "fr";
            cfg.Model.Kokoro.LengthScale = 1.0f;
            cfg.Model.NumThreads = fils;
            cfg.Model.Provider = "cpu";
            cfg.MaxNumSentences = 1;
            tts = new OfflineTts(cfg);
        }
        catch (Exception e) { Console.WriteLine("ERREUR\t" + e.Message.Replace('\n', ' ')); return 1; }
        Console.WriteLine("PRET");
        string ligne;
        while ((ligne = Console.ReadLine()) != null)
        {
            string[] p = ligne.TrimStart('﻿').Split('\t');
            if (p.Length < 6 || p[0] != "PARLE") { Console.WriteLine("ERREUR\tdemande incomprise"); continue; }
            try
            {
                int voix = int.Parse(p[1], CultureInfo.InvariantCulture);
                float vitesse = float.Parse(p[2], CultureInfo.InvariantCulture);
                string texte = string.Join(" ", p, 5, p.Length - 5);
                var audio = tts.Generate(texte, vitesse, voix);
                float[] wav = audio.Samples;
                int rate = audio.SampleRate;
                audio.Dispose();
                if (wav == null || wav.Length == 0) { Console.WriteLine("ERREUR\taucun son produit"); continue; }
                EcrireWav(p[4], wav, rate);
                Console.WriteLine("OK\t" + p[4] + "\t" + ((float)wav.Length / rate).ToString("0.00", CultureInfo.InvariantCulture));
            }
            catch (Exception e) { Console.WriteLine("ERREUR\t" + e.Message.Replace('\n', ' ')); }
        }
        tts.Dispose();
        return 0;
    }

    static void EcrireWav(string fichier, float[] audio, int rate)
    {
        using (var w = new BinaryWriter(File.Open(fichier, FileMode.Create)))
        {
            int taille = audio.Length * 2;
            w.Write(Encoding.ASCII.GetBytes("RIFF")); w.Write(36 + taille); w.Write(Encoding.ASCII.GetBytes("WAVE"));
            w.Write(Encoding.ASCII.GetBytes("fmt ")); w.Write(16); w.Write((short)1); w.Write((short)1);
            w.Write(rate); w.Write(rate * 2); w.Write((short)2); w.Write((short)16);
            w.Write(Encoding.ASCII.GetBytes("data")); w.Write(taille);
            foreach (float x in audio) w.Write((short)(Math.Max(-1f, Math.Min(1f, x)) * 32767));
        }
    }
}
