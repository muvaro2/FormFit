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
    

#training loop function
def train(model, train_loader, val_loader, epochs=50):
    criterion = nn.BCELoss() #measures how wrong the predictions are
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4) #updates the model's numbers after each run
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, patience=5, factor=0.5, verbose=True
    ) #reduces learning rate if the model stalls

    history = {'train': [], 'val': []} #stores the loss so it can be graphed
    best_val_loss = float('inf')

    for epoch in range(epochs):
        #Trains the model
        model.train()
        train_loss = 0.0
        for X, y in train_loader:
            optimizer.zero_grad() #clears previous run's gradients

            #forward and backward passes over the data
            loss = criterion(model(X), y)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            train_loss += loss.item()

        #Validates the model
        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for X, y in val_loader:
                val_loss += criterion(model(X), y).item()

        avg_train = train_loss / len(train_loader) #average loss
        avg_val   = val_loss   / len(val_loader)
        history['train'].append(avg_train)
        history['val'].append(avg_val)
        scheduler.step(avg_val)

        # Saves the best model
        if avg_val < best_val_loss:
            best_val_loss = avg_val
            torch.save(model.state_dict(), 'best_model.pth')

        print(f"Epoch {epoch+1:3d} | Train: {avg_train:.4f} | Val: {avg_val:.4f}")

    return history