import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt

class ConvNet1D(nn.Module):
    def __init__(self):
        super().__init__()
        self.layer1 = nn.Sequential(
            nn.Conv1d(9, 64, kernel_size=3),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.MaxPool1d(2), #reduces sample length by half
        
            nn.Conv1d(64, 128, kernel_size=3),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.MaxPool1d(2),
            
            nn.AdaptiveAvgPool1d(1)) #removes time by averaging
        self.layer2 = nn.Flatten()
        self.layer3 = nn.Sequential(
            nn.Linear(128, 32),
            nn.ReLU(),
            nn.Linear(32, 3), #classification into 3 metrics (elbow stability, scapular hiking, trunk compensation)
            nn.Sigmoid()) #classifies sample from 0-1 for each metric

    def forward(self, x):
        out = self.layer1(x)
        out = self.layer2(out)
        out = self.layer3(out)
        return out